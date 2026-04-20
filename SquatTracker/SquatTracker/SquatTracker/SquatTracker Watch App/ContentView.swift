// =====================================================
// APPLE WATCH APP - ContentView.swift
// =====================================================

import SwiftUI
import CoreMotion
import Combine

extension Color {
    static let burntOrange = Color(red: 191/255, green: 87/255, blue: 0/255)
    static let texasCream = Color(red: 255/255, green: 248/255, blue: 235/255)
}

struct ContentView: View {
    
    @StateObject var session = WatchSessionManager.shared
    let motion = CMMotionManager()
    let queue = OperationQueue()
    
    @State var running = false
    @State var status = "Ready"
    
    var body: some View {
        VStack(spacing: 10) {
            
            Text(status)
                .font(.headline)
                .foregroundColor(.burntOrange)
            
            Button(running ? "STOP" : "START") {
                running ? stop() : start()
            }
            .buttonStyle(.borderedProminent)
            .tint(.burntOrange)
            .foregroundColor(.white)
            
            Circle()
                .fill(running ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
        }
        .padding()
        .background(Color.black)
    }
    
    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        
        running = true
        status = "Streaming..."
        
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        
        motion.startDeviceMotionUpdates(to: queue) { data, error in
            
            guard let m = data else { return }
            
            let vals: [Double] = [
                m.userAcceleration.x,
                m.userAcceleration.y,
                m.userAcceleration.z,
                m.rotationRate.x,
                m.rotationRate.y,
                m.rotationRate.z,
                m.attitude.roll,
                m.attitude.pitch,
                m.attitude.yaw
            ]
            
            let packet = vals.withUnsafeBufferPointer {
                Data(buffer: $0)
            }
            
            session.sendPacket(packet)
        }
    }
    
    func stop() {
        running = false
        status = "Stopped"
        motion.stopDeviceMotionUpdates()
    }
}
