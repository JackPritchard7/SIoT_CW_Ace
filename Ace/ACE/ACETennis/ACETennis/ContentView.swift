import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showingUploadAlert = false
    @State private var uploadMessage = ""
    @State private var isUploading = false
    @State private var selectedStrokeType: String? = nil
    
    private let influxService = InfluxDBService()
    
    init() {
        print("🎾 ContentView initialized - Console is working!")
    }
    
    var body: some View {
        TabView {
            // Bluetooth Connection Tab
            BluetoothView()
                .environmentObject(bleManager)
                .tabItem {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
            
            // Practice Mode Tab
            PracticeModeView()
                .environmentObject(bleManager)
                .tabItem {
                    Label("Practice", systemImage: "play.circle.fill")
                }
            
            // Training Mode Tab (Data Collection)
            TrainingModeView()
                .environmentObject(bleManager)
                .tabItem {
                    Label("Training", systemImage: "chart.bar.doc.horizontal")
                }
            
            // Game Mode Tab (Tempo Training)
            GameModeView()
                .environmentObject(bleManager)
                .tabItem {
                    Label("Game", systemImage: "target")
                }
            
            // Session Stats Tab
            SessionStatsView(selectedStrokeType: $selectedStrokeType)
                .environmentObject(bleManager)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
        }
    }
}

// MARK: - Bluetooth Connection View
struct BluetoothView: View {
    @EnvironmentObject var bleManager: BLEManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: bleManager.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 80))
                    .foregroundColor(bleManager.isConnected ? .green : .gray)
                
                Text(bleManager.statusMessage)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    
                
                Spacer()
                
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
                        .cornerRadius(15)
                    }
                    .disabled(bleManager.isScanning)
                    .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 15) {
                        Text("\(bleManager.shots.count) shots recorded")
                            .font(.title2)
                            .bold()
                        
                        // Voice announcement toggle
                        Toggle(isOn: $bleManager.announceShots) {
                            HStack {
                                Image(systemName: bleManager.announceShots ? "speaker.wave.3.fill" : "speaker.slash.fill")
                                Text("Voice Announcements")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal, 40)
                        
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
                            .cornerRadius(15)
                        }
                        .padding(.horizontal, 40)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Bluetooth Connection")
        }
    }
}

// MARK: - Session Stats View
struct SessionStatsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @Binding var selectedStrokeType: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                if bleManager.shots.isEmpty {
                    VStack(spacing: 20) {
                        Spacer(minLength: 100)
                        Image(systemName: "chart.bar")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("No session data yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Connect and play to see stats!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let stats = bleManager.sessionStats
                    
                    VStack(spacing: 20) {
                        // Total Shots Card
                        StatCard(title: "Total Shots", value: "\(stats.total)", color: .blue)
                            .padding(.horizontal)
                        
                        // Stroke Type Cards (Tappable)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Stroke Breakdown")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            HStack {
                                StatCard(title: "Forehands", value: "\(stats.forehands)", color: .green)
                                    .onTapGesture {
                                        selectedStrokeType = "Forehand"
                                    }
                                StatCard(title: "Backhands", value: "\(stats.backhands)", color: .purple)
                                    .onTapGesture {
                                        selectedStrokeType = "Backhand"
                                    }
                                StatCard(title: "Serves", value: "\(stats.serves)", color: .red)
                                    .onTapGesture {
                                        selectedStrokeType = "Serve"
                                    }
                            }
                            .padding(.horizontal)
                            
                            Text("Tap to view details")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                        
                        Divider()
                            .padding(.vertical)
                        
                        // Recent Shots
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent Shots")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(bleManager.shots.reversed().prefix(10)) { shot in
                                ShotRow(shot: shot)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Session Stats")
        }
        .sheet(item: Binding(
            get: { selectedStrokeType.map { StrokeTypeWrapper(type: $0) } },
            set: { selectedStrokeType = $0?.type }
        )) { wrapper in
            StrokeDetailView(strokeType: wrapper.type, shots: bleManager.shots.filter { $0.stroke == wrapper.type })
        }
    }
}

// MARK: - Cloud Upload View
struct CloudUploadView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showingUploadAlert = false
    @State private var uploadMessage = ""
    @State private var isUploading = false
    
    private let influxService = InfluxDBService()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "cloud.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Upload Session Data")
                    .font(.title)
                    .bold()
                
                if bleManager.shots.isEmpty {
                    Text("No data to upload")
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 10) {
                        Text("\(bleManager.shots.count) shots ready to upload")
                            .font(.headline)
                        
                        Text("Data will be sent to InfluxDB Cloud")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
                
                Button(action: uploadToCloud) {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                        }
                        Text(isUploading ? "Uploading..." : "Upload to Cloud")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isUploading || bleManager.shots.isEmpty ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .disabled(isUploading || bleManager.shots.isEmpty)
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .navigationTitle("Cloud Upload")
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

// MARK: - Supporting Views

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
                Text(formattedTimestamp(shot.timestamp))
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

// Helper struct to make String Identifiable for sheet
struct StrokeTypeWrapper: Identifiable {
    let id = UUID()
    let type: String
}

// Detailed view showing all shots of a specific type
struct StrokeDetailView: View {
    let strokeType: String
    let shots: [TennisShot]
    @Environment(\.dismiss) var dismiss
    
    var strokeColor: Color {
        switch strokeType.lowercased() {
        case "forehand": return .green
        case "backhand": return .purple
        case "serve": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if shots.isEmpty {
                    Spacer()
                    Text("No \(strokeType)s recorded yet")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(shots.reversed()) { shot in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Shot #\(shot.shotNumber)")
                                        .font(.headline)
                                        .foregroundColor(strokeColor)
                                    Spacer()
                                    Text(formattedTimestamp(shot.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(spacing: 30) {
                                    VStack(alignment: .leading) {
                                        Text("Swing Speed")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(String(format: "%.1f", shot.swing)) mph")
                                            .font(.title3)
                                            .bold()
                                    }
                                    
                                    VStack(alignment: .leading) {
                                        Text("Top Spin")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(String(format: "%.1f", shot.spin)) dps")
                                            .font(.title3)
                                            .bold()
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing) {
                                        Text("Confidence")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(Int(shot.confidence * 100))%")
                                            .font(.title3)
                                            .bold()
                                            .foregroundColor(shot.confidence > 0.8 ? .green : .orange)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("\(strokeType)s (\(shots.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Helper function to format timestamp with milliseconds
func formattedTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, HH:mm:ss.SSS"
    return formatter.string(from: date)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BLEManager())
    }
}
