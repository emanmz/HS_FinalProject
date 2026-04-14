import SwiftUI
import CoreMotion
import CoreML
import WatchKit
import WatchConnectivity
import Combine

// MARK: - Haptics
class HapticManager {
    
    static let shared = HapticManager()
    private var last: Date = .distantPast
    private let cooldown: TimeInterval = 0.20
    
    func trigger(_ s: Double) {
        guard s > 0 else { return }
        guard Date().timeIntervalSince(last) > cooldown else { return }
        last = Date()
        
        let d = WKInterfaceDevice.current()
        
        switch s {
        case 0..<0.2: d.play(.click)
        case 0.2..<0.5: d.play(.notification)
        case 0.5..<0.8: d.play(.failure)
        default: d.play(.failure)
        }
    }
}

// MARK: - Watch View
struct ContentView: View {
    
    @State private var motionManager = CMMotionManager()
    private let queue = OperationQueue()
    
    private let model: SquatMLModel = {
        let config = MLModelConfiguration()
        return try! SquatMLModel(configuration: config)
    }()
    
    // Buffer
    @State private var buffer: [[Double]] = []
    private let window = 45
    
    // UI
    @State private var status = "Ready"
    @State private var reps = 0
    
    // Phase
    enum Phase { case standing, descending, bottom, ascending }
    @State private var phase: Phase = .standing
    @State private var lastPitch: Double = 0
    
    // ML smoothing
    @State private var labels: [String] = []
    private let labelWindow = 10
    
    // severity
    @State private var severity: Double = 0
    private let alpha = 0.3
    
    // WCSession
    private let session = WCSession.default
    
    var body: some View {
        VStack(spacing: 12) {
            
            Text(status)
                .font(.headline)
                .foregroundColor(status == "BAD FORM" ? .red : .green)
            
            Text("Reps: \(reps)")
            
            Button("START") {
                start()
            }
        }
    }
    
    // MARK: - Start
    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        session.activate()
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        
        motionManager.startDeviceMotionUpdates(to: queue) { motion, _ in
            guard let m = motion else { return }
            
            let f: [Double] = [
                m.userAcceleration.x,
                m.userAcceleration.y,
                m.userAcceleration.z,
                m.rotationRate.x,
                m.rotationRate.y,
                m.rotationRate.z,
                m.attitude.pitch,
                m.attitude.roll,
                m.attitude.yaw
            ]
            
            DispatchQueue.main.async {
                let filtered = f
                process(filtered, pitch: m.attitude.pitch)
            }
        }
    }
    
    // MARK: - Process
    func process(_ sample: [Double], pitch: Double) {
        
        buffer.append(sample)
        
        updatePhase(pitch)
        
        if buffer.count >= window {
            if buffer.count % 5 == 0 {
                runModel()
            }
            buffer.removeFirst()
        }
    }
    
    // MARK: - Phase
    func updatePhase(_ pitch: Double) {
        let d = pitch - lastPitch
        
        switch phase {
        case .standing:
            if d < -0.02 { phase = .descending }
            
        case .descending:
            if abs(d) < 0.005 { phase = .bottom }
            
        case .bottom:
            if d > 0.02 { phase = .ascending }
            
        case .ascending:
            if abs(pitch) < 0.1 {
                phase = .standing
                reps += 1
                
                session.sendMessage([
                    "event": "repComplete"
                ], replyHandler: nil)
                
                WKInterfaceDevice.current().play(.success)
            }
        }
        
        lastPitch = pitch
    }
    
    // MARK: - ML
    func runModel() {
        do {
            let arr = try MLMultiArray(shape: [1,45,9], dataType: .double)
            
            for t in 0..<45 {
                for f in 0..<9 {
                    arr[[0,NSNumber(value:t),NSNumber(value:f)]] =
                        NSNumber(value: buffer[t][f])
                }
            }
            
            let out = try model.prediction(input: SquatMLModelInput(input: arr))
            let label = out.classLabel
            
            labels.append(label)
            if labels.count > labelWindow { labels.removeFirst() }
            
            let knee = labels.filter { $0 == "KneeCave" }.count
            
            let raw = Double(knee) / Double(labelWindow)
            severity = alpha * raw + (1 - alpha) * severity
            
            DispatchQueue.main.async {
                
                status = severity > 0.5 ? "BAD FORM" : "GOOD FORM"
                
                HapticManager.shared.trigger(severity)
                
                session.sendMessage([
                    "label": label,
                    "phase": "\(phase)",
                    "severity": severity
                ], replyHandler: nil)
            }
            
        } catch {
            print(error)
        }
    }
}
