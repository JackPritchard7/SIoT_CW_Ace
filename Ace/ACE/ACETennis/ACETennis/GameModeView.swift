import SwiftUI
import AVFoundation
import Combine

struct GameModeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @StateObject private var gameManager = GameManager()
    @State private var selectedBPM: Double = 95.0
    
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
                } else if !gameManager.isActive {
                    // Setup Screen
                    ScrollView {
                        VStack(spacing: 25) {
                            Image(systemName: "target")
                                .font(.system(size: 80))
                                .foregroundColor(.orange)
                                .padding(.top, 20)
                            
                            Text("Game Mode")
                                .font(.largeTitle)
                                .bold()
                            
                            Text("Serve to start. Listen for the callout, wait 1 beat, then execute on the 4th click!")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                            
                            VStack(spacing: 15) {
                                Text("Metronome Speed")
                                    .font(.headline)
                                
                                Text("\(Int(selectedBPM)) BPM")
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.orange)
                                
                                Slider(value: $selectedBPM, in: 80...150, step: 2)
                                    .padding(.horizontal, 40)
                                
                                HStack {
                                    Text("80 BPM")
                                        .font(.caption)
                                    Spacer()
                                    Text("150 BPM")
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 40)
                            }
                            .padding(.vertical, 20)
                            
                            Button(action: {
                                gameManager.start(bleManager: bleManager, bpm: selectedBPM)
                            }) {
                                Text("Start Game")
                                    .font(.title2)
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(15)
                            }
                            .padding(.horizontal, 40)
                        }
                    }
                } else {
                    // Active Game Screen
                    VStack(spacing: 30) {
                        Spacer()
                        
                        // Score Display
                        HStack(spacing: 50) {
                            VStack {
                                Text("\(gameManager.score)")
                                    .font(.system(size: 60))
                                    .bold()
                                    .foregroundColor(.orange)
                                Text("Score")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack {
                                Text("\(gameManager.streak)")
                                    .font(.system(size: 60))
                                    .bold()
                                    .foregroundColor(.blue)
                                Text("Streak")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                            .padding(.horizontal, 40)
                        
                        // Status Display
                        VStack(spacing: 15) {
                            if gameManager.beatCount > 0 {
                                Text(gameManager.statusMessage)
                                    .font(.system(size: 50))
                                    .bold()
                                    .foregroundColor(.orange)
                            } else {
                                Text(gameManager.statusMessage)
                                    .font(.title2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            
                            if let callout = gameManager.currentCallout {
                                Text(callout)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            gameManager.stop()
                        }) {
                            Text("Stop Game")
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
            .navigationTitle("Game")
        }
        .onReceive(bleManager.$shots) { shots in
            if gameManager.isActive, let lastShot = shots.last {
                gameManager.handleShot(lastShot)
            }
        }
    }
}

class GameManager: ObservableObject {
    @Published var isActive = false
    @Published var statusMessage = "Get ready..."
    @Published var currentCallout: String?
    @Published var score = 0
    @Published var streak = 0
    @Published var beatCount = 0
    
    private var bleManager: BLEManager?
    private var bpm: Double = 95.0
    private var beatInterval: TimeInterval = 0.632
    
    private var expectedShot: String?
    private var shotWindowStart: Date?
    private var shotWindowEnd: Date?
    private var waitingForServe = true
    private var shotDeadlineTimer: Timer?
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastProcessedShotId: UUID?
    
    func start(bleManager: BLEManager, bpm: Double) {
        self.bleManager = bleManager
        self.bpm = bpm
        self.beatInterval = 60.0 / bpm
        
        isActive = true
        score = 0
        streak = 0
        waitingForServe = true
        statusMessage = "Serve to start"
        
        // Enable game mode (disables shot announcements)
        bleManager.inGameMode = true
        
        // Announce "Serve to start"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.announceShot("Serve to start")
        }
    }
    
    func stop() {
        isActive = false
        statusMessage = "Game ended"
        shotDeadlineTimer?.invalidate()
        bleManager?.inGameMode = false
        bleManager = nil
    }
    
    func handleShot(_ shot: TennisShot) {
        // Prevent processing the same shot twice
        guard shot.id != lastProcessedShotId else { return }
        lastProcessedShotId = shot.id
        
        if waitingForServe && shot.stroke.lowercased() == "serve" {
            // Serve detected - start the game
            waitingForServe = false
            startGameDrill()
        } else if !waitingForServe {
            // Check if shot was performed in the timing window
            if let expected = expectedShot, let windowStart = shotWindowStart, let windowEnd = shotWindowEnd {
                let shotTime = Date()
                let inTimeWindow = shotTime >= windowStart && shotTime <= windowEnd
                
                // Check if correct shot (treat Serve and Smash as equivalent)
                let detectedStroke = shot.stroke.lowercased()
                let expectedStroke = expected.lowercased()
                
                let wasCorrectShot: Bool
                if expectedStroke == "smash" {
                    // Smash expected - accept either Serve or Smash
                    wasCorrectShot = (detectedStroke == "serve" || detectedStroke == "smash")
                } else {
                    wasCorrectShot = (detectedStroke == expectedStroke)
                }
                
                if inTimeWindow && wasCorrectShot {
                    // Correct shot in time - just play success sound, no announcement
                    handleGameResult(correct: true, actualShot: shot.stroke)
                } else if inTimeWindow {
                    // Wrong shot in time - just play fail sound, no announcement
                    handleGameResult(correct: false, actualShot: shot.stroke)
                }
                // If outside window, wait for timer to handle it
            }
        }
    }
    
    private func startGameDrill() {
        // Pick random shot with weighted probabilities: 45% Forehand, 45% Backhand, 10% Smash
        let rand = Double.random(in: 0..<1.0)
        let shot: String
        if rand < 0.45 {
            shot = "Forehand"
        } else if rand < 0.90 {
            shot = "Backhand"
        } else {
            shot = "Smash"
        }
        expectedShot = shot
        currentCallout = shot
        
        beatCount = 0
        statusMessage = "Listen..."
        
        // Announce the shot first
        announceShot(expectedShot!)
        
        // Wait 1 beat after callout
        DispatchQueue.main.asyncAfter(deadline: .now() + beatInterval) {
            // Beat 1: First click
            self.playMetronomeTick()
            self.beatCount = 1
            self.statusMessage = "1..."
            
            // Beat 2: Second click
            DispatchQueue.main.asyncAfter(deadline: .now() + self.beatInterval) {
                self.playMetronomeTick()
                self.beatCount = 2
                self.statusMessage = "2..."
                
                // Beat 3: Third click
                DispatchQueue.main.asyncAfter(deadline: .now() + self.beatInterval) {
                    self.playMetronomeTick()
                    self.beatCount = 3
                    self.statusMessage = "3..."
                    
                    // Beat 4: Fourth click - shot should happen now (with 1s window on either side)
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.beatInterval) {
                        self.playMetronomeTick()
                        self.beatCount = 4
                        self.statusMessage = "NOW!"
                        
                        // Set the timing window: 1s before to 1s after the 4th beat
                        self.shotWindowStart = Date().addingTimeInterval(-1.0)
                        self.shotWindowEnd = Date().addingTimeInterval(1.0)
                        
                        // Deadline: After timing window closes (1s after 4th beat)
                        self.shotDeadlineTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                            self?.handleMissedShot()
                        }
                    }
                }
            }
        }
    }
    
    private func handleGameResult(correct: Bool, actualShot: String) {
        shotDeadlineTimer?.invalidate()
        shotWindowStart = nil
        shotWindowEnd = nil
        currentCallout = nil
        beatCount = 0
        
        if correct {
            // Correct shot! Continue the game
            score += 1
            streak += 1
            statusMessage = "Perfect! \(streak) in a row"
            playSuccessSound()
            
            // Wait one beat then continue with next shot
            DispatchQueue.main.asyncAfter(deadline: .now() + self.beatInterval) {
                self.startGameDrill()  // Continue game without serve
            }
        } else {
            // Wrong shot - game over
            let previousStreak = streak
            streak = 0
            statusMessage = "Game Over! Wrong shot. Score: \(score), Best streak: \(previousStreak)"
            playFailSound()
            announceShot("Wrong shot! You hit \(actualShot)")
            
            // Wait 2 seconds then prompt for serve to restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.resetForNextRound()
            }
        }
    }
    
    private func handleMissedShot() {
        shotWindowStart = nil
        shotWindowEnd = nil
        
        if expectedShot != nil {
            // Was waiting for a shot in game mode - game over
            let previousStreak = streak
            streak = 0
            statusMessage = "Game Over! Too slow. Score: \(score), Best streak: \(previousStreak)"
            playFailSound()
            announceShot("Too slow!")
            
            // Wait 2 seconds then prompt for serve to restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.resetForNextRound()
            }
        }
    }
    
    private func resetForNextRound() {
        waitingForServe = true
        currentCallout = nil
        expectedShot = nil
        beatCount = 0
        statusMessage = "Serve to start new game"
        
        // Announce "serve to start"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.announceShot("Serve to start")
        }
    }
    
    // MARK: - Audio
    
    private func playMetronomeTick() {
        AudioServicesPlaySystemSound(1103) // Tock sound
    }
    
    private func playSuccessSound() {
        AudioServicesPlaySystemSound(1054) // Success ding
    }
    
    private func playFailSound() {
        AudioServicesPlaySystemSound(1053) // Error buzz
    }
    
    private func announceShot(_ stroke: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: stroke)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.55
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
    }
}
