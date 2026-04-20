import SwiftUI
import Combine

extension Color {
    static let burntOrange = Color(red: 191/255, green: 87/255, blue: 0/255)
    static let texasCream = Color(red: 255/255, green: 248/255, blue: 235/255)
    static let texasDark = Color(red: 35/255, green: 25/255, blue: 20/255)
}

struct ContentView: View {
    @StateObject var manager = PhoneSessionManager()
    
    var goodReps: Int {
        manager.reports.filter { $0.good }.count
    }
    
    var badReps: Int {
        manager.reports.filter { !$0.good }.count
    }
    
    private var valgusColor: Color {
        switch manager.currentValgusLevel {
        case "high": return .red
        case "medium": return .orange
        case "low": return .yellow
        default: return .green
        }
    }
    
    private var valgusLabel: String {
        switch manager.currentValgusLevel {
        case "high": return "HIGH VALGUS"
        case "medium": return "MODERATE VALGUS"
        case "low": return "MILD VALGUS"
        default: return "STABLE"
        }
    }
    
    private var valgusFill: CGFloat {
        manager.liveValgusPercent > 100 ? 1.0 : CGFloat(manager.liveValgusPercent) / 100.0
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // HEADER
                VStack(spacing: 10) {
                    
                    Text(manager.status)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("\(manager.reps)")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("TOTAL REPS")
                        .foregroundColor(.white.opacity(0.9))
                    
                    HStack {
                        Text("Good: \(goodReps)")
                        Text("Bad: \(badReps)")
                    }
                    .foregroundColor(.white)
                    .font(.subheadline.bold())
                    
                    // LIVE VALGUS FEEDBACK
                    VStack(spacing: 6) {
                        Text(valgusLabel)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.2))
                                
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(valgusColor)
                                    .frame(width: geo.size.width * valgusFill)
                                    .animation(.easeInOut(duration: 0.15), value: valgusFill)
                            }
                        }
                        .frame(height: 10)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.burntOrange, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // REP LOG
                List(manager.reports) { rep in
                    HStack {
                        Circle()
                            .fill(rep.good ? .green : .red)
                            .frame(width: 14, height: 14)
                        
                        Text("Rep \(rep.rep)")
                            .foregroundColor(.texasDark)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("\(rep.valgus)%")
                                .bold()
                                .foregroundColor(.burntOrange)
                            
                            Text(rep.good ? "Good" : "Poor")
                                .font(.caption)
                                .foregroundColor(rep.good ? .green : .red)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.texasCream)
                }
                .scrollContentBackground(.hidden)
                .background(Color.texasCream)
            }
            .background(Color.texasCream)
            .navigationTitle("Texas Squat")
            .toolbar {
                Button("Reset") {
                    manager.reset()
                }
                .foregroundColor(.burntOrange)
            }
        }
        .accentColor(.burntOrange)
    }
}
