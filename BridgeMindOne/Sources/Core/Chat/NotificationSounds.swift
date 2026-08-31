//
// NotificationSounds.swift
// Audio notification sounds and playback
//

import Foundation
import AVFoundation

public enum NotificationSound: String, Codable, CaseIterable {
 case notchOpen = "notch-open"
 case notchClose = "notch-close"
 case cueBegin = "notch-cue-begin"
 case cueError = "notch-cue-error"
 case cueSent = "notch-cue-sent"
 case bell = "notification-bell"

 public var fileName: String { rawValue }
}

public actor NotificationSoundPlayer {
 public static let shared = NotificationSoundPlayer()
 private var audioPlayer: AVAudioPlayer?
 private var sounds: [NotificationSound: URL] = [:]

 public init() {
 loadSounds()
 }

 public func play(_ sound: NotificationSound) {
 guard let url = sounds[sound] else { return }

 Task {
 do {
 audioPlayer = try AVAudioPlayer(contentsOf: url)
 audioPlayer?.volume = 0.5
 audioPlayer?.play()
 } catch {
 // Silent fail
 }
 }
 }

 public func playCueBegin() { play(.cueBegin) }
 public func playCueError() { play(.cueError) }
 public func playCueSent() { play(.cueSent) }
 public func playBell() { play(.bell) }

 public func loadSounds() {
 let soundsURL = Bundle.main.bundleURL
 .appendingPathComponent("Contents/Resources/sounds")

 for sound in NotificationSound.allCases {
 let fileURL = soundsURL.appendingPathComponent("\(sound.fileName).wav")
 if FileManager.default.fileExists(atPath: fileURL.path) {
 sounds[sound] = fileURL
 }
 }
 }
}

public actor SystemNotificationDelivering {
 public static let shared = SystemNotificationDelivering()

 public func deliver(title: String, body: String) {
 let center = UNUserNotificationCenter.current()

 let content = UNMutableNotificationContent()
 content.title = title
 content.body = body
 content.sound = .default

 let request = UNNotificationRequest(
 identifier: UUID().uuidString,
 content: content,
 trigger: nil
 )

 center.add(request) { error in
 if let error {
 print("Notification error: \(error)")
 }
 }
 }

 public func requestAuthorization() async -> Bool {
 await UNUserNotificationCenter.current()
 .requestAuthorization(options: [.alert, .sound, .badge])
 }
}
