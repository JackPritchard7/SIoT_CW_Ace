import SwiftUI
import AVFoundation
import Combine

// MARK: - Training Mode Manager (Match Data Collection for Analysis)
class TrainingModeManager: ObservableObject {
    @Published var isActive = false
    @Published var sessionShots: [TennisShot] = []
    @Published var statusMessage = "Ready to train"
    @Published var isUploading = false
    @Published var uploadMessage = ""
    
    weak var bleManager: BLEManager?
    private var sessionStartTime: Date?
    
    func startSession() {
        isActive = true
        sessionShots = []
        sessionStartTime = Date()
        statusMessage = "Training session active"
        bleManager?.announceShots = true  // Enable shot announcements
    }
    
    func stopSession() {
        isActive = false
        statusMessage = "Session complete: \(sessionShots.count) shots recorded"
        bleManager?.announceShots = false
    }
    
    func handleShot(_ shot: TennisShot) {
        guard isActive else { return }
        
        // Store shot in session data
        sessionShots.append(shot)
        statusMessage = "Recorded: \(shot.stroke) (\(sessionShots.count) total)"
    }
    
    func clearSession() {
        sessionShots = []
        uploadMessage = ""
        statusMessage = "Session cleared"
    }
    
    func uploadToInfluxDB() async {
        guard let influxService = bleManager?.influxService else {
            uploadMessage = "❌ InfluxDB not configured"
            return
        }
        
        guard !sessionShots.isEmpty else {
            uploadMessage = "❌ No shots to upload"
            return
        }
        
        isUploading = true
        uploadMessage = "Uploading \(sessionShots.count) shots..."
        
        do {
            try await influxService.uploadShotsAsync(sessionShots)
            uploadMessage = "✅ Successfully uploaded \(sessionShots.count) shots to InfluxDB"
        } catch {
            uploadMessage = "❌ Upload failed: \(error.localizedDescription)"
        }
        
        isUploading = false
    }
    
    // MARK: - Session Statistics
    var sessionStats: (forehands: Int, backhands: Int, serves: Int, avgSwing: Double, maxSwing: Double, avgSpin: Double) {
        let forehands = sessionShots.filter { $0.stroke.lowercased() == "forehand" }.count
        let backhands = sessionShots.filter { $0.stroke.lowercased() == "backhand" }.count
        let serves = sessionShots.filter { $0.stroke.lowercased() == "serve" }.count
        
        let avgSwing = sessionShots.isEmpty ? 0.0 : sessionShots.map { $0.swing }.reduce(0, +) / Double(sessionShots.count)
        let maxSwing = sessionShots.map { $0.swing }.max() ?? 0.0
        let avgSpin = sessionShots.isEmpty ? 0.0 : sessionShots.map { $0.spin }.reduce(0, +) / Double(sessionShots.count)
        
        return (forehands, backhands, serves, avgSwing, maxSwing, avgSpin)
    }
}

// MARK: - Training Mode View (Match Data Collection)
struct TrainingModeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @StateObject private var trainingManager = TrainingModeManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if !bleManager.isConnected {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Connect to ESP32 first")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if !trainingManager.isActive {
                    // Setup Screen
                    ScrollView {
                        VStack(spacing: 25) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 80))
                                .foregroundColor(.blue)
                                .padding(.top, 20)
                            
                            Text("Training Mode")
                                .font(.largeTitle.weight(.bold))
                            
                            Text("Record shot data during a match for analysis. All shots are classified and stored with swing speed, spin rate, and timestamps. Use this mode to track your performance during practice matches.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                            
                            // Session Stats (if previous session exists)
                            if !trainingManager.sessionShots.isEmpty {
                                VStack(spacing: 15) {
                                    Text("Previous Session Summary")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    let stats = trainingManager.sessionStats
                                    
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                        StatCard(title: "Total Shots", value: "\(trainingManager.sessionShots.count)", color: .blue)
                                        StatCard(title: "Forehands", value: "\(stats.forehands)", color: .green)
                                        StatCard(title: "Backhands", value: "\(stats.backhands)", color: .purple)
                                        StatCard(title: "Serves", value: "\(stats.serves)", color: .orange)
                                        StatCard(title: "Avg Speed", value: String(format: "%.1f mph", stats.avgSwing), color: .red)
                                        StatCard(title: "Max Speed", value: String(format: "%.1f mph", stats.maxSwing), color: .red)
                                    }
                                    .padding(.horizontal, 30)
                                    
                                    // Upload Button
                                    if trainingManager.uploadMessage.isEmpty {
                                        Button(action: {
                                            Task {
                                                await trainingManager.uploadToInfluxDB()
                                            }
                                        }) {
                                            HStack {
                                                if trainingManager.isUploading {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                } else {
                                                    Image(systemName: "icloud.and.arrow.up")
                                                }
                                                Text(trainingManager.isUploading ? "Uploading..." : "Upload to InfluxDB")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(trainingManager.isUploading ? Color.gray : Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                        }
                                        .disabled(trainingManager.isUploading)
                                        .padding(.horizontal, 30)
                                    } else {
                                        Text(trainingManager.uploadMessage)
                                            .font(.subheadline)
                                            .foregroundColor(trainingManager.uploadMessage.contains("✅") ? .green : .red)
                                            .multilineTextAlignment(.center)
                                            .padding()
                                            .padding(.horizontal, 30)
                                    }
                                    
                                    // Clear Session Button
                                    Button(action: {
                                        trainingManager.clearSession()
                                    }) {
                                        HStack {
                                            Image(systemName: "trash")
                                            Text("Clear Session Data")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red.opacity(0.2))
                                        .foregroundColor(.red)
                                        .cornerRadius(10)
                                    }
                                    .padding(.horizontal, 30)
                                }
                                .padding(.vertical, 20)
                            }
                            
                            // Start Button
                            Button(action: {
                                trainingManager.startSession()
                            }) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                    Text("Start Training Session")
                                }
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 50)
                        }
                    }
                } else {
                    // Active Training Session
                    VStack(spacing: 25) {
                        // Status
                        VStack(spacing: 10) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                            
                            Text("Recording Session")
                                .font(.title.weight(.bold))
                            
                            Text(trainingManager.statusMessage)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Live Stats
                        let stats = trainingManager.sessionStats
                        
                        VStack(spacing: 20) {
                            Text("Live Session Stats")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                StatCard(title: "Total Shots", value: "\(trainingManager.sessionShots.count)", color: .blue)
                                StatCard(title: "Forehands", value: "\(stats.forehands)", color: .green)
                                StatCard(title: "Backhands", value: "\(stats.backhands)", color: .purple)
                                StatCard(title: "Serves", value: "\(stats.serves)", color: .orange)
                                StatCard(title: "Avg Speed", value: String(format: "%.1f mph", stats.avgSwing), color: .red)
                                StatCard(title: "Max Speed", value: String(format: "%.1f mph", stats.maxSwing), color: .red)
                            }
                        }
                        .padding(.horizontal, 30)
                        
                        Spacer()
                        
                        // Stop Button
                        Button(action: {
                            trainingManager.stopSession()
                        }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Session")
                            }
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 50)
                    }
                }
            }
            .navigationTitle("Training Mode")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            trainingManager.bleManager = bleManager
        }
        .onReceive(bleManager.$shots) { shots in
            if let lastShot = shots.last, trainingManager.isActive {
                trainingManager.handleShot(lastShot)
            }
        }
    }
}

struct TrainingModeView_Previews: PreviewProvider {
    static var previews: some View {
        TrainingModeView()
            .environmentObject(BLEManager())
    }
}
