import Foundation
import MultipeerConnectivity
import YSwift

class ConnectionManager: NSObject, ObservableObject {
    private static let service = "yswift-todolist"
    
    @Published var peers: [MCPeerID] = []
    
    private var session: MCSession
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private var nearbyServiceBrowser: MCNearbyServiceBrowser
    private var nearbyServiceAdvertiser: MCNearbyServiceAdvertiser
    private let `protocol`: YProtocol
    
    var onConnectionStateChanged: ((MCSessionState) -> Void)?
    var onUpdatesReceived: (() -> Void)?
    
    init(document: YDocument) {
        self.protocol = YProtocol(document: document)
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        nearbyServiceAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: nil,
            serviceType: ConnectionManager.service)
        nearbyServiceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: ConnectionManager.service)
        super.init()
        session.delegate = self
        nearbyServiceAdvertiser.delegate = self
        nearbyServiceBrowser.delegate = self
        nearbyServiceAdvertiser.startAdvertisingPeer()
        nearbyServiceBrowser.startBrowsingForPeers()
    }
    
    func invitePeer(_ peerID: MCPeerID) {
        nearbyServiceBrowser.invitePeer(peerID, to: session, withContext: nil, timeout: TimeInterval(120))
    }
    
    func sendEveryone(_ message: YSyncMessage) {
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print(error.localizedDescription)
        }
    }
}

extension ConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onConnectionStateChanged?(state)
        switch state {
        case .connected:
            let message = self.protocol.handleConnectionStarted()
            sendEveryone(message)
            print("Connected to: \(peerID.displayName)")
        case .notConnected:
            print("Not connected: \(peerID.displayName)")
        case .connecting:
            print("Connecting to: \(peerID.displayName)")
        @unknown default:
            print("Unknown state: \(state)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(YSyncMessage.self, from: data) else { return }
        switch message.kind {
        case .STEP_1:
            let response = self.protocol.handleStep1(message.buffer)
            sendEveryone(response)
        case .STEP_2:
            self.protocol.handleStep2(message.buffer, completionHandler: onUpdatesReceived!)
        case .UPDATE:
            self.protocol.handleUpdate(message.buffer, completionHandler: onUpdatesReceived!)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.session)
    }
}


extension ConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        invitePeer(peerID)
        if !peers.contains(peerID) {
            peers.append(peerID)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        guard let index = peers.firstIndex(of: peerID) else { return }
        peers.remove(at: index)
    }
}
