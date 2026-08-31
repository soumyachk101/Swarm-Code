//
// AudioRecording.swift
// Voice dictation via fn key
//

import Foundation
import AVFoundation
import Speech

public enum DictationState: Equatable {
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
 checkPermissions()
 }

 public func startListening() async throws {
 guard let audioEngine else { throw DictationError.noAudioEngine }

 state = .listening
 audioPlayer.playCueBegin()

 try audioEngine.start()
 }

 public func stopListening() async -> String? {
 audioEngine?.stop()
 audioPlayer.playCueSent()

 guard let result = await recognitionTask?.result?.bestTranscription.formattedString else {
 state = .idle
 return nil
 }

 state = .idle
 return result
 }

 public func cancelListening() {
 audioEngine?.stop()
 recognitionTask?.cancel()
 state = .idle
 }

 // MARK: - Private

 private func checkPermissions() {
 Task {
 // Check microphone permission
 let micStatus = await AVCaptureDevice.requestAccess(for: .audio)

 // Check speech recognition permission
 let speechStatus = await SFSpeechRecognizer.requestAuthorization()

 if micStatus == .denied || speechStatus != .authorized {
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

 recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
 if let error {
 print("Recognition error: \(error)")
 return
 }

 guard let result else { return }

 if result.isFinal {
 let transcript = result.bestTranscription.formattedString
 Task { [weak self] in
 self?.state = .idle
 }
 }
 }

 self.audioEngine = engine
 }
}

public enum DictationError: Error, Equatable {
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
