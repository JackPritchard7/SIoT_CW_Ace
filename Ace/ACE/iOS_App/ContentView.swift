import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showingUploadAlert = false
    @State private var uploadMessage = ""
    @State private var isUploading = false
    
    private let influxService = InfluxDBService()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Status
                VStack(spacing: 10) {
                    Image(systemName: bleManager.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 50))
                        .foregroundColor(bleManager.isConnected ? .green : .gray)
                    
                    Text(bleManager.statusMessage)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    if !bleManager.isConnected {
                        Button(action: {
                            bleManager.startScanning()
                        }) {
                            HStack {
                                if bleManager.isScanning {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text(bleManager.isScanning ? "Scanning..." : "Connect to ESP32")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bleManager.isScanning ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(bleManager.isScanning)
                        .padding(.horizontal)
                    } else {
                        Button(action: {
                            bleManager.disconnect()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Disconnect")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                
                Divider()
                
                // Session Stats
                if !bleManager.shots.isEmpty {
                    let stats = bleManager.sessionStats
                    
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Session Stats")
                            .font(.title2)
                            .bold()
                        
                        HStack {
                            StatCard(title: "Total Shots", value: "\(stats.total)", color: .blue)
                            StatCard(title: "Avg Swing", value: String(format: "%.0f mph", stats.avgSwing), color: .orange)
                        }
                        
                        HStack {
                            StatCard(title: "Forehands", value: "\(stats.forehands)", color: .green)
                            StatCard(title: "Backhands", value: "\(stats.backhands)", color: .purple)
                            StatCard(title: "Serves", value: "\(stats.serves)", color: .red)
                        }
                        
                        StatCard(title: "Avg Spin", value: String(format: "%.0f dps", stats.avgSpin), color: .cyan)
                    }
                    .padding()
                    
                    Divider()
                    
                    // Recent Shots List
                    VStack(alignment: .leading) {
                        Text("Recent Shots")
                            .font(.title3)
                            .bold()
                            .padding(.horizontal)
                        
                        List(bleManager.shots.reversed().prefix(10)) { shot in
                            ShotRow(shot: shot)
                        }
                        .listStyle(PlainListStyle())
                    }
                    
                    // Upload Button
                    Button(action: uploadToCloud) {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "cloud.fill")
                            }
                            Text(isUploading ? "Uploading..." : "Upload Session to Cloud")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isUploading ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isUploading || bleManager.shots.isEmpty)
                    .padding()
                    
                } else {
                    Spacer()
                    
                    VStack {
                        Image(systemName: "tennisball")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("No shots yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Connect to ESP32 and start playing!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("🎾 ACE Tennis")
            .alert(isPresented: $showingUploadAlert) {
                Alert(
                    title: Text(uploadMessage.contains("✅") ? "Success" : "Error"),
                    message: Text(uploadMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func uploadToCloud() {
        isUploading = true
        
        influxService.uploadShots(bleManager.shots) { result in
            DispatchQueue.main.async {
                isUploading = false
                
                switch result {
                case .success(let count):
                    uploadMessage = "✅ Successfully uploaded \(count) shots to InfluxDB!"
                case .failure(let error):
                    uploadMessage = "❌ Upload failed: \(error.localizedDescription)"
                }
                
                showingUploadAlert = true
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title)
                .bold()
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct ShotRow: View {
    let shot: TennisShot
    
    var strokeColor: Color {
        switch shot.stroke.lowercased() {
        case "forehand": return .green
        case "backhand": return .purple
        case "serve": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("#\(shot.shotNumber) - \(shot.stroke)")
                    .font(.headline)
                    .foregroundColor(strokeColor)
                Text(shot.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("\(Int(shot.swing)) mph")
                    .font(.subheadline)
                    .bold()
                Text("\(Int(shot.spin)) dps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BLEManager())
    }
}
