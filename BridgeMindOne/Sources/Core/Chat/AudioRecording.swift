//
// AudioRecording.swift
// Voice dictation via fn key
//

import Foundation
import AVFoundation
import Speech

public enum DictationState: Equatable, Sendable {
    case idle
    case listening
    case processing
    case error(String)
}

public actor AudioRecording {
    public static let shared = AudioRecording()
    public private(set) var state: DictationState = .idle

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()
    private let audioPlayer = NotificationSoundPlayer.shared

    public init() {
        Task {
            await self.checkPermissions()
        }
    }

    public func startListening() async throws {
        if audioEngine == nil {
            try setupAudioEngine()
        }
        guard let audioEngine else { throw DictationError.noAudioEngine }

        state = .listening
        await audioPlayer.playCueBegin()

        try audioEngine.start()
    }

    public func stopListening() async -> String? {
        audioEngine?.stop()
        await audioPlayer.playCueSent()
        state = .idle
        return nil
    }

    public func cancelListening() {
        audioEngine?.stop()
        recognitionTask?.cancel()
        state = .idle
    }

    // MARK: - Private

    private func checkPermissions() async {
        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        if !micStatus || speechStatus != .authorized {
            state = .error("Microphone or speech recognition permission denied")
        }
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let error {
                print("Recognition error: \(error)")
                return
            }

            guard let result else { return }

            if result.isFinal {
                Task { [weak self] in
                    await self?.setState(.idle)
                }
            }
        }

        self.audioEngine = engine
    }

    private func setState(_ newState: DictationState) {
        self.state = newState
    }
}

public enum DictationError: Error, Equatable, Sendable {
    case noAudioEngine
    case permissionDenied
    case recognitionFailed(String)

    public var localizedDescription: String {
        switch self {
        case .noAudioEngine: return "Audio engine not configured"
        case .permissionDenied: return "Permission denied"
        case .recognitionFailed(let msg): return "Recognition failed: \(msg)"
        }
    }
}
