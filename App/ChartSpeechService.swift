import AVFoundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class ChartSpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var playback = SpeechPlayback()
    private(set) var voiceOverActive = UIAccessibility.isVoiceOverRunning
    private(set) var statusMessage = ""
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var utteranceID: ObjectIdentifier?
    @ObservationIgnored private var lastAnnouncement = ""

    override init() {
        super.init()
        synthesizer.delegate = self
        // OS-managed separate playback session; no recording permission or audio files.
        synthesizer.usesApplicationAudioSession = false
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, UIApplication.didEnterBackgroundNotification] {
            center.addObserver(self, selector: #selector(interruption(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(voiceOverChanged(_:)), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    func synchronize(with snapshot: BarChart.TrustedSnapshot?) {
        if playback.synchronize(snapshot) {
            utteranceID = nil
            synthesizer.stopSpeaking(at: .immediate)
            statusMessage = ""
        }
    }
    func play(_ content: VerifiedSpeechContent) {
        voiceOverActive = UIAccessibility.isVoiceOverRunning
        guard !voiceOverActive else {
            stop(interrupted: true)
            statusMessage = "VoiceOver is active. Use the readable chart text; separate speech playback stays off."
            return
        }
        guard playback.start(content, requestID: UUID()) else { return }
        // Clear the old utterance identity before stopping so old callbacks cannot
        // cancel or complete a replacement request.
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: content.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utteranceID = ObjectIdentifier(utterance)
        statusMessage = ""
        synthesizer.speak(utterance)
    }
    func pause() {
        guard playback.state == .speaking, let id = playback.requestID else { return }
        if synthesizer.pauseSpeaking(at: .word) {
            playback.receive(.paused, requestID: id)
            announce("Reading paused.")
        } else { statusMessage = "Reading could not pause yet. Try again or stop reading." }
    }
    func resume() {
        voiceOverActive = UIAccessibility.isVoiceOverRunning
        if voiceOverActive { stop(interrupted: true); return }
        guard !voiceOverActive, playback.state == .paused, let id = playback.requestID else { return }
        if synthesizer.continueSpeaking() { playback.receive(.resumed, requestID: id) }
        else { statusMessage = "Reading could not resume. Stop and read again." }
    }
    func stop(interrupted: Bool = false) {
        let wasActive = playback.active
        playback.stop(interrupted: interrupted)
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        if wasActive { statusMessage = playback.state.rawValue; announce(statusMessage) }
    }
    func replay() {
        guard !playback.active, let content = playback.content else { return }
        play(content)
    }

    private func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning, text != lastAnnouncement else { return }
        lastAnnouncement = text
        AccessibilityNotification.Announcement(text).post()
    }

    @objc nonisolated private func interruption(_ notification: Notification) {
        // Objective-C notification/delegate callbacks may arrive on any thread.
        // These short bridges carry no chart text and do no background work.
        Task { @MainActor [weak self] in self?.stop(interrupted: true) }
    }
    @objc nonisolated private func voiceOverChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.voiceOverActive = UIAccessibility.isVoiceOverRunning
            if self.voiceOverActive { self.stop(interrupted: true) }
        }
    }

    private func receive(_ event: SpeechPlayback.Event, utteranceID: ObjectIdentifier) {
        guard self.utteranceID == utteranceID, let request = playback.requestID else { return }
        playback.receive(event, requestID: request)
        if event == .finished || event == .cancelled { self.utteranceID = nil }
    }
    nonisolated private func deliver(_ event: SpeechPlayback.Event, utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(event, utteranceID: identifier) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { deliver(.started, utterance: utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { deliver(.finished, utterance: utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { deliver(.cancelled, utterance: utterance) }
}
