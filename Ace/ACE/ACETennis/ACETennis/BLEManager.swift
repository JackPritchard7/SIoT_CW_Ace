import Foundation
import CoreBluetooth
import Combine
import AVFoundation

// Shot data model
struct TennisShot: Identifiable, Codable {
    let id = UUID()
    let shotNumber: Int
    let stroke: String
    let swing: Double
    let spin: Double
    let confidence: Double
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case shotNumber = "shot"
        case stroke
        case swing
        case spin
        case confidence = "conf"
        case timestamp = "ts"
    }
    
    init(shotNumber: Int, stroke: String, swing: Double, spin: Double, confidence: Double, timestamp: Date = Date()) {
        self.shotNumber = shotNumber
        self.stroke = stroke
        self.swing = swing
        self.spin = spin
        self.confidence = confidence
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shotNumber = try container.decode(Int.self, forKey: .shotNumber)
        stroke = try container.decode(String.self, forKey: .stroke)
        swing = try container.decode(Double.self, forKey: .swing)
        spin = try container.decode(Double.self, forKey: .spin)
        confidence = try container.decode(Double.self, forKey: .confidence)
        
        // Handle timestamp - convert from millis if needed
        if let ts = try? container.decode(Double.self, forKey: .timestamp) {
            timestamp = Date(timeIntervalSince1970: ts / 1000.0)
        } else {
            timestamp = Date()
        }
    }
}

class BLEManager: NSObject, ObservableObject {
    // BLE UUIDs - must match ESP32
    private let serviceUUID = CBUUID(string: "Update_Here")
    private let shotCharUUID = CBUUID(string: "Update_Here")
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var shotCharacteristic: CBCharacteristic?
    
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var shots: [TennisShot] = []
    @Published var statusMessage = "Tap to connect to ESP32"
    @Published var announceShots = true  // Toggle for voice announcements
    @Published var inGameMode = false  // Track if in game mode (disables announcements)
    @Published var maxSwingSpeed: Double = 0.0  // Track maximum swing speed
    
    let influxService = InfluxDBService()  // InfluxDB service for data upload
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth is not available"
            return
        }
        
        shots.removeAll()
        maxSwingSpeed = 0.0
        isScanning = true
        statusMessage = "Scanning for ACE Tennis..."
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        
        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.isScanning == true {
                self?.stopScanning()
                if self?.isConnected == false {
                    self?.statusMessage = "Device not found. Tap to retry."
                }
            }
        }
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    var sessionStats: (total: Int, forehands: Int, backhands: Int, serves: Int, avgSwing: Double, maxSwing: Double, avgSpin: Double) {
        let total = shots.count
        let forehands = shots.filter { $0.stroke.lowercased() == "forehand" }.count
        let backhands = shots.filter { $0.stroke.lowercased() == "backhand" }.count
        let serves = shots.filter { $0.stroke.lowercased() == "serve" }.count
        let avgSwing = total > 0 ? shots.map { $0.swing }.reduce(0, +) / Double(total) : 0
        let maxSwing = shots.map { $0.swing }.max() ?? 0.0
        let avgSpin = total > 0 ? shots.map { $0.spin }.reduce(0, +) / Double(total) : 0
        
        return (total, forehands, backhands, serves, avgSwing, maxSwing, avgSpin)
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Ready to connect"
        case .poweredOff:
            statusMessage = "Bluetooth is off"
        case .unauthorized:
            statusMessage = "Bluetooth permission needed"
        case .unsupported:
            statusMessage = "Bluetooth not supported"
        default:
            statusMessage = "Bluetooth unavailable"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("🔍 Discovered: \(peripheral.name ?? "Unknown")")
        
        self.peripheral = peripheral
        stopScanning()
        statusMessage = "Connecting..."
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to \(peripheral.name ?? "Unknown")")
        isConnected = true
        statusMessage = "Connected - Waiting for shots..."
        
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("❌ Disconnected")
        isConnected = false
        statusMessage = "Disconnected. Tap to reconnect."
        self.peripheral = nil
        shotCharacteristic = nil
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        statusMessage = "Connection failed. Tap to retry."
        isConnected = false
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([shotCharUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == shotCharUUID {
                shotCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("✅ Subscribed to shot notifications")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        print("📲 didUpdateValueFor called!")
        
        guard characteristic.uuid == shotCharUUID else {
            print("⚠️ Wrong characteristic")
            return
        }
        
        guard let data = characteristic.value else {
            print("⚠️ No data")
            return
        }
        
        // Debug: print raw data
        print("📊 Data length: \(data.count) bytes")
        print("📊 Raw hex: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            print("⚠️ Can't decode UTF8 - trying ASCII...")
            if let asciiString = String(data: data, encoding: .ascii) {
                print("📥 ASCII: \(asciiString)")
            }
            return
        }
        
        print("📥 Received: \(jsonString)")
        
        // Parse JSON manually to handle ESP32 timestamp format
        if let jsonData = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let shotNum = json["shot"] as? Int,
           let stroke = json["stroke"] as? String,
           let swing = json["swing"] as? Double,
           let spin = json["spin"] as? Double,
           let conf = json["conf"] as? Double {
            
            let shot = TennisShot(
                shotNumber: shotNum,
                stroke: stroke,
                swing: swing,
                spin: spin,
                confidence: conf,
                timestamp: Date()
            )
            
            DispatchQueue.main.async {
                self.shots.append(shot)
                self.statusMessage = "Shot #\(shot.shotNumber) - \(shot.stroke)"
                
                // Update max swing speed
                if shot.swing > self.maxSwingSpeed {
                    self.maxSwingSpeed = shot.swing
                }
                
                // Announce the shot only if enabled and NOT in game mode
                if self.announceShots && !self.inGameMode {
                    self.announceShot(stroke)
                }
            }
        }
    }
    
    // MARK: - Voice Announcement
    private func announceShot(_ stroke: String) {
        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: stroke)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5  // Slightly faster than default
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
    }
}
