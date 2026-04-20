import Foundation
import WatchConnectivity
import WatchKit
import CoreMotion
import Combine

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    
    private let session = WCSession.default
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    
    @Published var connected = false
    
    private var lastHapticTime = Date.distantPast
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
        startMotion()
    }
    
    func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 25.0
        
        motion.startDeviceMotionUpdates(to: queue) { data, error in
            guard let m = data else { return }
            
            let ax = m.gravity.x + m.userAcceleration.x
            let ay = m.gravity.y + m.userAcceleration.y
            let az = m.gravity.z + m.userAcceleration.z
            
            let packet: [Double] = [
                ax, ay, az,
                m.rotationRate.x,
                m.rotationRate.y,
                m.rotationRate.z,
                m.attitude.roll,
                m.attitude.pitch,
                m.attitude.yaw
            ]
            
            let d = packet.withUnsafeBufferPointer { Data(buffer: $0) }
            self.sendPacket(d)
        }
    }
    
    func sendPacket(_ data: Data) {
        try? session.updateApplicationContext(["imu": data])
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let level = message["valgus"] as? String else { return }

        let now = Date()

        let cooldown: Double
        switch level {
        case "high": cooldown = 0.25
        case "medium": cooldown = 0.8
        default: cooldown = 1.2
        }

        guard now.timeIntervalSince(lastHapticTime) > cooldown else { return }
        lastHapticTime = now

        DispatchQueue.main.async {
            switch level {
            case "medium":
                WKInterfaceDevice.current().play(.directionUp)

            case "high":
                WKInterfaceDevice.current().play(.notification)

            default:
                WKInterfaceDevice.current().play(.click)
            }
        }

        // forward to iPhone UI
        if session.isReachable {
            session.sendMessage(["valgus": level], replyHandler: nil, errorHandler: nil)
        }
    }
    
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.connected = activationState == .activated
        }
    }
}
