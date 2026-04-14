import SwiftUI
import WatchConnectivity
import Combine

// MARK: - Rep Detail
struct RepData: Identifiable {
    let id = UUID()
    let index: Int
    let severity: Double
}

// MARK: - Manager
class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    
    @Published var status = "Waiting..."
    @Published var reps: [RepData] = []
    @Published var currentRep = 0
    
    private var session = WCSession.default
    
    // rep tracking
    private var inRep = false
    private var tempSeverity: Double = 0
    private var repCount = 0
    
    override init() {
        super.init()
        
        guard WCSession.isSupported() else { return }
        
        session.delegate = self
        session.activate()
    }
    
    // MARK: - REQUIRED (activation)
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // optional debug
        print("Watch session activated: \(activationState.rawValue)")
    }
    
    // MARK: - REQUIRED (iOS lifecycle)
    func sessionDidBecomeInactive(_ session: WCSession) {
        // iOS only
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    
    // MARK: - Receive data
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any]) {
        
        DispatchQueue.main.async {
            
            // Rep completed event
            if let event = message["event"] as? String,
               event == "repComplete" {
                
                self.reps.append(
                    RepData(index: self.repCount,
                            severity: self.tempSeverity)
                )
                
                self.repCount += 1
                self.tempSeverity = 0
                self.status = "Rep \(self.repCount) complete"
                return
            }
            
            // Live severity updates
            if let severity = message["severity"] as? Double {
                self.tempSeverity = severity
                self.status = severity > 0.5 ? "BAD FORM" : "GOOD FORM"
            }
            
            // Optional label debugging
            if let label = message["label"] as? String {
                print("Label: \(label)")
            }
        }
    }
}

// MARK: - UI
struct ContentView: View {
    
    @StateObject var manager = PhoneSessionManager()
    
    var body: some View {
        VStack(spacing: 20) {
            
            Text(manager.status)
                .font(.title2)
                .bold()
            
            Text("Reps: \(manager.reps.count)")
                .font(.headline)
            
            // Rep timeline
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(manager.reps) { rep in
                        HStack {
                            Text("Rep \(rep.index + 1)")
                            Spacer()
                            Text(String(format: "%.0f%% valgus", rep.severity * 100))
                        }
                        .padding()
                        .background(
                            Color.red.opacity(rep.severity)
                        )
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding()
    }
}
