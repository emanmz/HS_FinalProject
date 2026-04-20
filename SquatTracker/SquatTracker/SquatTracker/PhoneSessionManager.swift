import Foundation
import WatchConnectivity
import CoreML
import SwiftUI
import Combine

struct RepReport: Identifiable {
    let id = UUID()
    let rep: Int
    let valgus: Int
    let good: Bool
}

final class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    
    @Published var status = "Waiting for Watch"
    @Published var reps = 0
    @Published var reports: [RepReport] = []
    @Published var liveValgusPercent: Int = 0
    @Published var currentZAccel: Double = 0
    @Published var currentValgusLevel: String = "none"
    
    private let session = WCSession.default
    private var model: SquatMLModel = {
        let config = MLModelConfiguration()
        return try! SquatMLModel(configuration: config)
    }()
    
    private var buffer: [[Double]] = []
    private let window = 44
    
    private var baselineSamples: [[Double]] = []
    private var calibrated = false
    private var standingXBaseline: Double = 0
    
    private enum RepState {
        case atTop, goingDown, atBottom, goingUp
    }
    
    private var repState: RepState = .atTop
    private var maxZReached: Double = 0
    private var lastRepTime = Date.distantPast
    private var repLocked = false
    private var topStableTime: TimeInterval = 0
    
    private let targetZThreshold = -0.7
    private let returnZThreshold = -0.2
    private let startMovingZ = -0.35
    private let ascentTriggerZ = -0.5

    private var valgusFiltered: Double = 0
    private var lastFeedbackTime = Date.distantPast
    private var repValgusSamples: [Double] = []

    override init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let packet = applicationContext["imu"] as? Data else { return }
        let vals = packet.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
        DispatchQueue.main.async { self.process(vals) }
    }

    // real-time valgus level from watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let level = message["valgus"] as? String else { return }
        DispatchQueue.main.async {
            self.currentValgusLevel = level
        }
    }

    func process(_ sample: [Double]) {
        guard sample.count == 9 else { return }

        if !calibrated {
            collectBaseline(sample)
            return
        }

        let az = sample[2]
        currentZAccel = az
        
        updateGForceRepLogic(az)

        buffer.append(sample)
        if buffer.count > window { buffer.removeFirst() }
        if buffer.count == window { runModel() }
    }

    private func collectBaseline(_ sample: [Double]) {
        baselineSamples.append(sample)
        status = "Calibrating... Stand Still"
        
        if baselineSamples.count >= 50 {
            standingXBaseline = baselineSamples.map { $0[0] }.reduce(0,+) / 50.0
            calibrated = true
            status = "Ready"
        }
    }

    private func updateGForceRepLogic(_ az: Double) {
        let dt = 0.04

        switch repState {
        case .atTop:
            if repLocked {
                if az > returnZThreshold {
                    topStableTime += dt
                    if topStableTime > 0.5 { repLocked = false }
                }
                return
            }

            if az < startMovingZ {
                repState = .goingDown
                maxZReached = az
                repValgusSamples.removeAll()
            }

        case .goingDown:
            maxZReached = min(maxZReached, az)
            
            if maxZReached <= targetZThreshold && az > ascentTriggerZ {
                repState = .goingUp
            }

        case .goingUp:
            if az > returnZThreshold {
                let now = Date()
                if now.timeIntervalSince(lastRepTime) > 1.0 {
                    finishRep()
                    lastRepTime = now
                    repLocked = true
                    topStableTime = 0
                }
                repState = .atTop
            }

            if az > returnZThreshold && maxZReached > targetZThreshold {
                repState = .atTop
            }

        default: break
        }
    }

    private func runModel() {
        do {
            let arr = try MLMultiArray(shape: [1, 9, 44], dataType: .double)
            for f in 0..<9 {
                for t in 0..<44 {
                    arr[[0, f, t] as [NSNumber]] = NSNumber(value: buffer[t][f])
                }
            }

            let out = try model.prediction(input: SquatMLModelInput(input: arr))
            let mlBad = out.classLabel == "KneeCave"
            
            let pitch = buffer.last![7]
            let pitchScore = min(abs(pitch) / 0.3, 1.0)
            let rawScore = min(1.0, 0.5 * (mlBad ? 1.0 : 0.0) + 0.8 * pitchScore)

            valgusFiltered = 0.4 * valgusFiltered + 0.6 * rawScore
            
            if repState == .goingDown || repState == .goingUp {
                repValgusSamples.append(valgusFiltered)
            }
            
            liveValgusPercent = Int(valgusFiltered * 100)

            if repState == .goingDown {
                sendRealtimeFeedback(valgusFiltered)
            }
        } catch { print(error) }
    }

    // UPDATED: reduced spam feedback with intensity-based cooldown
    private func sendRealtimeFeedback(_ score: Double) {
        let now = Date()

        let level = score > 0.5 ? "high" : (score > 0.25 ? "medium" : "none")

        let cooldown: Double
        switch level {
        case "high": cooldown = 0.35
        case "medium": cooldown = 0.9
        default: return
        }

        guard now.timeIntervalSince(lastFeedbackTime) > cooldown else { return }
        lastFeedbackTime = now

        if session.isReachable {
            session.sendMessage(["valgus": level], replyHandler: nil, errorHandler: nil)
        }
    }

    private func finishRep() {
        reps += 1
        let avg = repValgusSamples.reduce(0,+) / max(Double(repValgusSamples.count), 1)
        let percent = Int(avg * 100)
        reports.insert(RepReport(rep: reps, valgus: percent, good: percent < 40), at: 0)
    }

    func reset() {
        reps = 0
        reports.removeAll()
        buffer.removeAll()
        baselineSamples.removeAll()
        calibrated = false
        repState = .atTop
        repLocked = false
        status = "Stand Still..."
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
}
