//
//  ContentView.swift
//  ringgame
//
//  Created by Aaron Anderson on 11/27/25.
//

import SwiftUI
import AVFoundation
import AudioToolbox
import UIKit
import Combine

struct ContentView: View {
    @State private var phase: CGFloat = 0
    @State private var resultText: String? = nil
    @State private var hasTapped: Bool = false
    @State private var animationSpeed: CGFloat = 0.35 // phase units per second
    @State private var currentStreak: Int = 0
    @State private var lastStreak: Int = 0
    @State private var combo: Int = 0
    
    @AppStorage("topScores") private var topScoresData: Data = Data()
    @State private var showScores: Bool = false
    @State private var bestStreak: Int = 0

    @State private var isPaused: Bool = false
    @State private var showCountdown: Bool = true
    @State private var countdown: Int = 3
    @State private var showConfetti: Bool = false
    @State private var flashLose: Bool = false
    @State private var musicPlayer: AVAudioPlayer?
    @AppStorage("musicEnabled") private var musicEnabled: Bool = true
    @AppStorage("musicVolume") private var musicVolume: Double = 0.4
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("difficultyPreset") private var difficultyPreset: String = "Normal"
    @State private var showSettings: Bool = false
    @AppStorage("visualPreset") private var visualPreset: String = "Classic"
    @AppStorage("restartAfterLoss") private var restartAfterLoss: Bool = false

    private func playWinFeedback() {
        #if canImport(UIKit)
        if hapticsEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        #endif
        AudioServicesPlaySystemSound(1103) // Soft 'Tink' like success
    }

    private func playLoseFeedback() {
        #if canImport(UIKit)
        if hapticsEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        #endif
        AudioServicesPlaySystemSound(1053) // Subtle short tone for failure
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning!"
        case 12..<17: return "Good afternoon!"
        default: return "Good evening!"
        }
    }
    
    private func getTopScores() -> [Int] {
        (try? JSONDecoder().decode([Int].self, from: topScoresData)).map { Array($0.prefix(5)) } ?? []
    }

    private func setTopScores(_ scores: [Int]) {
        let trimmed = Array(scores.prefix(5))
        if let data = try? JSONEncoder().encode(trimmed) {
            topScoresData = data
        }
    }

    private func recordScore(_ score: Int) {
        guard score > 0 else { return }
        var scores = getTopScores()
        scores.append(score)
        scores.sort(by: >)
        setTopScores(scores)
        bestStreak = scores.first ?? max(bestStreak, score)
    }

    private func startBackgroundMusic() {
        guard musicEnabled else { return }
        if let player = musicPlayer, !player.isPlaying {
            player.play()
            return
        }
        guard let url = Bundle.main.url(forResource: "theme", withExtension: "mp3") ??
                        Bundle.main.url(forResource: "theme", withExtension: "m4a") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = Float(musicVolume)
            player.prepareToPlay()
            player.play()
            musicPlayer = player
        } catch {
            print("Music error: \(error)")
        }
    }

    private func stopBackgroundMusic() {
        musicPlayer?.stop()
    }

    private func triggerWinEffects() {
        showConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showConfetti = false
        }
    }

    private func triggerLoseFlash() {
        flashLose = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            flashLose = false
        }
    }
    
    private func applyDifficultyPreset() {
        switch difficultyPreset {
        case "Easy":
            animationSpeed = 0.30
        case "Hard":
            animationSpeed = min(0.45 + CGFloat(currentStreak) * 0.06, 1.4)
        default:
            animationSpeed = min(0.35 + CGFloat(currentStreak) * 0.045, 1.2)
        }
    }
    
    private var themeHint: String {
        switch visualPreset {
        case "Neon":
            return "Tap when the red ring is between the neon rings!"
        case "Pastel":
            return "Tap when the red ring is between the pastel rings!"
        default:
            return "Tap when the red ring is between the gold rings!"
        }
    }
    
    private var isPerfectCueActive: Bool {
        // Mirror the same geometry used in PlayfieldView and tap evaluation
        let baseSize: CGFloat = 180
        let gap: CGFloat = 90
        let maxOversize: CGFloat = 160
        let minUndersize: CGFloat = 2
        let startSize = baseSize + maxOversize
        let endSize = minUndersize
        let size1 = max(endSize, startSize - (startSize - endSize) * phase)
        let size2 = max(endSize, size1 - gap)
        guard size2 < baseSize && baseSize < size1 else { return false }
        let mid = (size1 + size2) / 2
        let thickness = max(8, min(24, (size1 - size2) * 0.30))
        return abs(baseSize - mid) <= (thickness / 2)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Ring Game")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .leading, endPoint: .trailing))
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Text("Streak: \(currentStreak)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button { showScores = true } label: {
                        HStack(spacing: 6) { Image(systemName: "list.number"); Text("High Scores") }
                            .font(.headline)
                    }
                    .buttonStyle(.borderless)
                }
                HStack(spacing: 16) {
                    Button { isPaused.toggle() } label: {
                        Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        musicEnabled.toggle()
                        if musicEnabled { startBackgroundMusic() } else { stopBackgroundMusic() }
                    } label: {
                        Label(musicEnabled ? "Music On" : "Music Off", systemImage: musicEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .buttonStyle(.bordered)
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline)
            }
            
            PlayfieldView(
                phase: phase,
                visualPreset: visualPreset,
                flashLose: flashLose,
                showConfetti: showConfetti,
                showCountdown: showCountdown,
                countdown: countdown
            )
            
            if isPerfectCueActive {
                Text("PERFECT!")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            
            Text("Aim for PERFECT timing!")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if combo > 0 {
                Text("Combo x\(combo)!")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            Button(action: {
                if isPaused || showCountdown { return }
                if musicEnabled { startBackgroundMusic() }
                // Clear any prior lose message on a new tap
                if resultText == "You lose." { resultText = nil }

                // Evaluate win/lose at the moment of tap
                // Recompute the same sizing values used in the PlayfieldView to ensure consistency
                let baseSize: CGFloat = 180
                let gap: CGFloat = 90
                let maxOversize: CGFloat = 160
                let minUndersize: CGFloat = 2
                let startSize = baseSize + maxOversize
                let endSize = minUndersize
                let size1 = max(endSize, startSize - (startSize - endSize) * phase)
                let size2 = max(endSize, size1 - gap)
                
                // Perfect if the red ring lies near the midpoint band between yellow rings
                var isPerfect = false
                if size2 < baseSize && baseSize < size1 {
                    let mid = (size1 + size2) / 2
                    let thickness = max(8, min(24, (size1 - size2) * 0.30))
                    // Consider perfect if the red ring diameter is within the band thickness/2 around the midpoint
                    isPerfect = abs(baseSize - mid) <= (thickness / 2)
                }

                hasTapped = true
                if size2 < baseSize && baseSize < size1 {
                    resultText = "You win!"
                    currentStreak += 1
                    applyDifficultyPreset()
                    if isPerfect { combo += 1 } else { combo = 0 }
                    if currentStreak > bestStreak {
                        bestStreak = currentStreak
                        recordScore(bestStreak)
                    }
                    playWinFeedback()
                    triggerWinEffects()
                } else {
                    combo = 0
                    resultText = "You lose."
                    lastStreak = currentStreak
                    currentStreak = 0
                    recordScore(bestStreak)
                    switch difficultyPreset {
                    case "Easy": animationSpeed = 0.30
                    case "Hard": animationSpeed = 0.45
                    default: animationSpeed = 0.35
                    }
                    playLoseFeedback()
                    triggerLoseFlash()
                    if restartAfterLoss {
                        isPaused = true
                        showCountdown = true
                        countdown = 3
                        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                            if countdown > 0 { countdown -= 1 }
                            else { t.invalidate(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCountdown = false; isPaused = false } }
                        }
                    }
                }
            }) {
                Text("Tap!")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.blue))
                    .foregroundColor(.white)
            }

            if resultText == "You lose." {
                VStack(spacing: 4) {
                    Text("Your High Score: \(lastStreak)")
                        .font(.subheadline)
                    Text("Score to Beat: \(bestStreak)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(greeting)
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            Text(themeHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            bestStreak = getTopScores().first ?? 0
            startBackgroundMusic()
            // Begin a 3..2..1..GO countdown
            showCountdown = true
            countdown = 3
            applyDifficultyPreset()
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                if countdown > 0 { countdown -= 1 }
                else { t.invalidate(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCountdown = false } }
            }
        }
        .onReceive(Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()) { _ in
            if isPaused || showCountdown { return }
            // Advance phase based on a constant speed (units per second)
            let dt: CGFloat = 1.0 / 60.0
            phase += animationSpeed * dt
            // Compute current sizes to decide when to reset (only when inner ring reaches near center)
            let baseSize: CGFloat = 180
            let gap: CGFloat = 90
            let maxOversize: CGFloat = 160
            let minUndersize: CGFloat = 2
            let startSize = baseSize + maxOversize
            let endSize = minUndersize
            let size1 = max(endSize, startSize - (startSize - endSize) * phase)
            let size2 = max(endSize, size1 - gap)
            // If the inner ring is effectively at the center, restart the cycle
            if size2 <= minUndersize + 0.5 {
                phase = 0
                // Removed clearing of resultText and hasTapped to keep lose message visible until next tap
            }
        }
        .onChange(of: musicVolume) { _, newValue in
            musicPlayer?.volume = Float(newValue)
        }
        .sheet(isPresented: $showScores) {
            NavigationStack {
                List(Array(getTopScores().enumerated()), id: \.offset) { idx, score in
                    HStack {
                        Text("#\(idx + 1)")
                        Spacer()
                        Text("\(score)")
                    }
                }
                .navigationTitle("Top 5 Scores")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showScores = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Audio") {
                        Toggle("Music", isOn: $musicEnabled)
                            .onChange(of: musicEnabled) { _, enabled in
                                if enabled { startBackgroundMusic() } else { stopBackgroundMusic() }
                            }
                        HStack {
                            Text("Music Volume")
                            Slider(value: $musicVolume, in: 0...1)
                        }
                        Toggle("Haptics", isOn: $hapticsEnabled)
                    }
                    Section("Difficulty") {
                        Picker("Preset", selection: $difficultyPreset) {
                            Text("Easy").tag("Easy")
                            Text("Normal").tag("Normal")
                            Text("Hard").tag("Hard")
                        }
                        .pickerStyle(.segmented)
                        Text("Current speed: \(String(format: "%.2f", animationSpeed))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Visuals") {
                        Picker("Theme", selection: $visualPreset) {
                            Text("Classic").tag("Classic")
                            Text("Neon").tag("Neon")
                            Text("Pastel").tag("Pastel")
                        }
                        .pickerStyle(.segmented)
                        Toggle("Restart with countdown after loss", isOn: $restartAfterLoss)
                        Toggle("Show cycle progress", isOn: .constant(true)) // placeholder for future user control
                        Toggle("Show perfect hint", isOn: .constant(true)) // placeholder for future user control
                    }
                    Section("About") {
                        Text("Aim to tap when the red ring is between the gold rings. Streaks increase difficulty!")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showSettings = false }
                    }
                }
            }
        }
    }
}

struct PlayfieldView: View {
    // Inputs
    let phase: CGFloat
    let visualPreset: String
    let flashLose: Bool
    let showConfetti: Bool
    let showCountdown: Bool
    let countdown: Int

    var ringGradient: LinearGradient {
        switch visualPreset {
        case "Neon": return LinearGradient(colors: [.cyan, .mint], startPoint: .top, endPoint: .bottom)
        case "Pastel": return LinearGradient(colors: [.yellow.opacity(0.9), .pink.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        default: return LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
        }
    }
    var borderGradient: LinearGradient {
        switch visualPreset {
        case "Neon": return LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Pastel": return LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    var bandColor: Color {
        switch visualPreset {
        case "Neon": return Color.cyan.opacity(0.28)
        case "Pastel": return Color.pink.opacity(0.28)
        default: return Color.green.opacity(0.25)
        }
    }

    var body: some View {
        ZStack {
            // Parameters
            let baseSize: CGFloat = 180
            let gap: CGFloat = 90
            let maxOversize: CGFloat = 160
            let minUndersize: CGFloat = 2
            let startSize = baseSize + maxOversize
            let endSize = minUndersize
            let size1 = max(endSize, startSize - (startSize - endSize) * phase)
            let size2 = max(endSize, size1 - gap)

            // Perfect window band (midway between yellow rings) — only when achievable
            if size2 < baseSize && baseSize < size1 {
                // Midpoint diameter between the two yellow rings
                let mid = (size1 + size2) / 2
                // Band thickness as a gentle fraction of the gap so it sits clearly between
                let gapBetween = (size1 - size2)
                let thickness = max(8, min(24, gapBetween * 0.30))
                // Optional inset for visual separation from ring edges
                let visualInset: CGFloat = 0
                Circle()
                    .strokeBorder(bandColor.opacity(0.5), lineWidth: thickness)
                    .frame(width: mid - visualInset, height: mid - visualInset)

                // Highlight when the red ring is centered within the perfect band
                let inPerfect = abs(baseSize - mid) <= (thickness / 2)
                if inPerfect {
                    let pulse = 1 + 0.06 * CGFloat(sin(Double(phase) * 2.0 * .pi))
                    Circle()
                        .stroke(Color.green, lineWidth: 6)
                        .frame(width: baseSize + 8, height: baseSize + 8)
                        .scaleEffect(pulse)
                        .opacity(0.9)
                        .shadow(color: .green.opacity(0.7), radius: 12)
                }
            }

            // Base red ring
            Circle()
                .stroke(Color.red, lineWidth: 12)
                .frame(width: baseSize, height: baseSize)

            // Gold rings
            Circle()
                .stroke(ringGradient, lineWidth: 10)
                .shadow(color: .yellow.opacity(0.3), radius: 6 * (1 - phase))
                .frame(width: size1, height: size1)
            Circle()
                .stroke(ringGradient, lineWidth: 10)
                .shadow(color: .yellow.opacity(0.3), radius: 6 * (1 - phase))
                .frame(width: size2, height: size2)
        }
        .frame(width: 300, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(borderGradient, lineWidth: 6)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.red.opacity(flashLose ? 0.25 : 0.0))
                .animation(.easeOut(duration: 0.2), value: flashLose)
        )
        .overlay( ConfettiBurst(active: showConfetti) )
        .overlay( CountdownOverlay(show: showCountdown, count: countdown).clipShape(RoundedRectangle(cornerRadius: 20)) )
    }
}

struct ConfettiBurst: View {
    let active: Bool
    var body: some View {
        ZStack {
            if active {
                ForEach(0..<14, id: \.self) { i in
                    Circle()
                        .fill([Color.pink, .yellow, .green, .blue, .orange, .purple][i % 6])
                        .frame(width: 8, height: 8)
                        .offset(
                            x: cos(Double(i) / 14.0 * .pi * 2.0) * 10,
                            y: sin(Double(i) / 14.0 * .pi * 2.0) * 10
                        )
                        .scaleEffect(active ? 3.0 : 0.1)
                        .opacity(active ? 0.0 : 1.0)
                        .animation(.easeOut(duration: 0.8), value: active)
                }
            }
        }
    }
}

struct CountdownOverlay: View {
    let show: Bool
    let count: Int
    var body: some View {
        Group {
            if show {
                ZStack {
                    Color.black.opacity(0.3)
                    Text(count > 0 ? "\(count)" : "GO!")
                        .font(.system(size: 56, weight: .heavy))
                        .foregroundColor(.white)
                        .transition(.scale)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

