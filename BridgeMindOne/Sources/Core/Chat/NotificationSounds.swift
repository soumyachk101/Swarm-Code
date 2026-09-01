//
// NotificationSounds.swift
// Audio notification sounds and playback
//

import Foundation
import AVFoundation
import UserNotifications

public enum NotificationSound: String, Codable, CaseIterable, Sendable {
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
        self.sounds = Self.discoverSounds()
    }

    private static func discoverSounds() -> [NotificationSound: URL] {
        var found: [NotificationSound: URL] = [:]
        let searchDirectories = [
            Bundle.main.resourceURL?.appendingPathComponent("Sounds"),
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Sounds"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            URL(fileURLWithPath: "Sources/Resources/Sounds")
        ].compactMap { $0 }

        for sound in NotificationSound.allCases {
            for dir in searchDirectories {
                let fileURL = dir.appendingPathComponent("\(sound.fileName).wav")
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    found[sound] = fileURL
                    break
                }
            }
        }
        return found
    }

    public func play(_ sound: NotificationSound) {
        guard let url = sounds[sound] else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 0.5
            audioPlayer?.play()
        } catch {
            // Silent fail
        }
    }

    public func playCueBegin() { play(.cueBegin) }
    public func playCueError() { play(.cueError) }
    public func playCueSent() { play(.cueSent) }
    public func playBell() { play(.bell) }

    public func reloadSounds() {
        self.sounds = Self.discoverSounds()
    }
}

public actor SystemNotificationDelivering {
    public static let shared = SystemNotificationDelivering()

    public init() {}

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
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}
