//
// PerformanceMonitor.swift
// Performance metrics collection and reporting
//

import Foundation
import os
import Darwin

// MARK: - Performance Metrics

public struct PerformanceMetrics: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpuUsage: Double
    public let memoryUsage: UInt64
    public let memoryPeak: UInt64
    public let activeAgents: Int
    public let activePlugins: Int
    public let messagesPerSecond: Double
    public let toolCallsPerMinute: Int

    public init(
        timestamp: Date = Date(),
        cpuUsage: Double = 0,
        memoryUsage: UInt64 = 0,
        memoryPeak: UInt64 = 0,
        activeAgents: Int = 0,
        activePlugins: Int = 0,
        messagesPerSecond: Double = 0,
        toolCallsPerMinute: Int = 0
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.memoryPeak = memoryPeak
        self.activeAgents = activeAgents
        self.activePlugins = activePlugins
        self.messagesPerSecond = messagesPerSecond
        self.toolCallsPerMinute = toolCallsPerMinute
    }
}

// MARK: - Performance Monitor

public actor PerformanceMonitor {
    public static let shared = PerformanceMonitor()

    private var metrics: [PerformanceMetrics] = []
    private var watchdogs: [PerformanceWatchdog] = []
    private let logger = Logger(subsystem: "ai.bridgemind.one", category: "performance")
    private var alertThreshold = 80.0
    private var samplingTask: Task<Void, Never>?

 public init() {
 Task { [weak self] in
 await self?.startSamplingTask()
 }
 }

 private nonisolated func startSamplingTask() {
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                await self?.sample()
            }
        }
    }

    private func sample() {
        let m = currentMetrics()
        recordMetrics(m)
    }

    public func recordMetrics(_ m: PerformanceMetrics) {
        self.metrics.append(m)

        if self.metrics.count > 1000 {
            self.metrics.removeFirst(100)
        }

        checkThresholds(m)
    }

    public func currentMetrics() -> PerformanceMetrics {
        let (cpu, _) = hostInfo()
        let (mem, peak) = memoryInfo()

        return PerformanceMetrics(
            cpuUsage: cpu,
            memoryUsage: mem,
            memoryPeak: peak,
            activeAgents: 0,
            activePlugins: 0
        )
    }

    public func metricsReport() -> [PerformanceMetrics] {
        Array(metrics.suffix(100))
    }

    public func resetMetrics() {
        metrics.removeAll()
    }

    public func setAlertThreshold(_ threshold: Double) {
        alertThreshold = threshold
    }

    public func addWatchdog(_ watchdog: PerformanceWatchdog) {
        watchdogs.append(watchdog)
    }

    public func removeWatchdog(_ watchdog: PerformanceWatchdog) {
        watchdogs.removeAll { $0.id == watchdog.id }
    }

    private func checkThresholds(_ metrics: PerformanceMetrics) {
        if metrics.cpuUsage > alertThreshold {
            for watchdog in watchdogs {
                watchdog.thresholdExceeded(metrics)
            }
        }
    }

    private func hostInfo() -> (cpuUsage: Double, loadAverage: Double) {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        if kr == KERN_SUCCESS {
            let user = Double(cpuInfo.cpu_ticks.0)
            let system = Double(cpuInfo.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3)
            let total = user + system + idle + nice
            let usage = total > 0 ? (user + system + nice) / total * 100.0 : 0
            return (usage, 0)
        }

        return (0, 0)
    }

    private func memoryInfo() -> (used: UInt64, peak: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }

        if kr == KERN_SUCCESS {
            return (UInt64(info.resident_size), UInt64(info.resident_size_max))
        }

        return (0, 0)
    }
}

// MARK: - Performance Watchdog

public protocol PerformanceWatchdog: Sendable {
    var id: String { get }
    func thresholdExceeded(_ metrics: PerformanceMetrics)
}

public struct DefaultPerformanceWatchdog: PerformanceWatchdog {
    public let id = "default.watchdog"
    private let logger = Logger(subsystem: "ai.bridgemind.one", category: "watchdog")

    public init() {}

    public func thresholdExceeded(_ metrics: PerformanceMetrics) {
        logger.warning("CPU usage exceeded threshold: \(metrics.cpuUsage)%")
    }
}

// MARK: - Logger

public struct LoggerWrapper {
    public static func log(level: OSLogType, message: String) {
        let log = OSLog(subsystem: "ai.bridgemind.one", category: "app")
        os_log("%{public}@", log: log, type: level, message)
    }
}
