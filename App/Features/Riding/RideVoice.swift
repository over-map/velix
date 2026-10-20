import AVFoundation
import CoreHaptics
@preconcurrency import FerrostarCore
import Foundation
import UIKit

/// The voice control in MapControlStack (P5): All → Alerts only → Mute.
enum VoiceMode: String, CaseIterable, Sendable {
    case all, alerts, mute

    var next: VoiceMode {
        switch self {
        case .all: .alerts
        case .alerts: .mute
        case .mute: .all
        }
    }
    /// Turn-by-turn instructions are spoken.
    var speaksTurns: Bool { self == .all }
    /// Hazard alerts are spoken (the haptic fires in every mode).
    var speaksHazards: Bool { self != .mute }
}

/// One speech synthesizer for Ferrostar's turn instructions and the app's hazard prompts, so they queue rather than
/// talk over each other, and an audio session the app owns: ducks music, keeps speaking with the screen locked
/// (UIBackgroundModes audio).
@MainActor
final class RideVoice {
    let synthesizer = AVSpeechSynthesizer()
    /// Handed to FerrostarCore; muted outside `VoiceMode.all`.
    let turns: SpokenInstructionObserver
    private(set) var mode: VoiceMode = .all

    init() {
        turns = SpokenInstructionObserver(synthesizer: synthesizer, isMuted: false, managesAudioSession: false)
    }

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                         options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func set(_ mode: VoiceMode) {
        self.mode = mode
        if turns.isMuted == mode.speaksTurns { turns.toggleMute() }   // Ferrostar only offers a toggle
        if mode == .mute { synthesizer.stopSpeaking(at: .word) }
    }

    func cycle() { set(mode.next) }

    /// A hazard alert (≤ 6 words, P5 `HZ`): spoken next, ahead of any queued turn instruction.
    func speakHazard(_ text: String) {
        guard mode.speaksHazards else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-GB")
        u.prefersAssistiveTechnologySettings = true
        synthesizer.speak(u)
    }
}

/// Two short taps when a hazard is close (P5 S4e; HANDOFF open question 5: tune on a handlebar mount).
@MainActor
final class RideHaptics {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
    }

    func hazard() {
        guard let engine, let pattern = try? Self.twoTaps() else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        try? engine.start()
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }

    static func twoTaps() throws -> CHHapticPattern {
        let tap = { (t: TimeInterval) in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
            ], relativeTime: t)
        }
        return try CHHapticPattern(events: [tap(0), tap(0.18)], parameters: [])
    }
}
