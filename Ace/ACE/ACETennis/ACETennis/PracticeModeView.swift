import SwiftUI
import AVFoundation
import Combine

struct PracticeModeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var isActive = false
    @State private var statusMessage = "Ready to practice"
    @State private var shotCount = 0
    @State private var lastProcessedShotId: UUID?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                if !bleManager.isConnected {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Connect to ESP32 first")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if !isActive {
                    // Setup Screen
                    ScrollView {
                        VStack(spacing: 25) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.green)
                                .padding(.top, 20)
                            
                            Text("Practice Mode")
                                .font(.largeTitle)
                                .bold()
                            
                            Text("Hit any shot and hear it announced. Perfect for warming up and testing accuracy.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                            
                            Spacer().frame(height: 20)
                            
                            Button(action: {
                                startPractice()
                            }) {
                                Text("Start Practice")
                                    .font(.title2)
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(15)
                            }
                            .padding(.horizontal, 40)
                        }
                    }
                } else {
                    // Active Practice Screen
                    VStack(spacing: 40) {
                        Spacer()
                        
                        Image(systemName: "figure.tennis")
                            .font(.system(size: 100))
                            .foregroundColor(.green)
                        
                        Text(statusMessage)
                            .font(.title)
                            .bold()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("\(shotCount) shots detected")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        // Max Swing Speed Display
                        if bleManager.maxSwingSpeed > 0 {
                            VStack(spacing: 8) {
                                Text("MAX SWING SPEED")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fontWeight(.medium)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.1f", bleManager.maxSwingSpeed))
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                        .foregroundColor(.orange)
                                    Text("mph")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.orange.opacity(0.1))
                            )
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            stopPractice()
                        }) {
                            Text("Stop Practice")
                                .font(.title2)
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Practice")
        }
        .onReceive(bleManager.$shots) { shots in
            if isActive, let lastShot = shots.last {
                if lastShot.id != lastProcessedShotId {
                    lastProcessedShotId = lastShot.id
                    shotCount += 1
                    statusMessage = "Nice \(lastShot.stroke)!"
                }
            }
        }
    }
    
    private func startPractice() {
        isActive = true
        shotCount = 0
        statusMessage = "Hit any shot!"
        
        // Enable announcements and disable game mode
        bleManager.announceShots = true
        bleManager.inGameMode = false
    }
    
    private func stopPractice() {
        isActive = false
        statusMessage = "Practice ended"
        bleManager.inGameMode = false
    }
}
