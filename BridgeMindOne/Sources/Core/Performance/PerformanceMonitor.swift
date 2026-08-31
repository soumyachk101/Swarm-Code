//
// PerformanceMonitor.swift
// Performance metrics collection and reporting
//

import Foundation
import os

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
 private var sampleTimer: Timer?
 private var alertThreshold = 80.0 // 80% CPU threshold

 public init() {
 startSampling()
 }

 public func recordMetrics(_ metrics: PerformanceMetrics) {
 self.metrics.append(metrics)

 // Keep last 1000 samples
 if self.metrics.count > 1000 {
 self.metrics.removeFirst(100)
 }

 // Check thresholds
 checkThresholds(metrics)
 }

 public func currentMetrics() -> PerformanceMetrics {
 let info = hostInfo()
 let memInfo = memoryInfo()

 return PerformanceMetrics(
 cpuUsage: info.cpuUsage,
 memoryUsage: memInfo.used,
 memoryPeak: memInfo.peak,
 activeAgents: 0, // populated by caller
 activePlugins: 0 // populated by caller
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

 // MARK: - Private

 private func startSampling() {
 sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
 Task {
 guard let self else { return }
 let metrics = self.currentMetrics()
 self.recordMetrics(metrics)
 }
 }
 }

 private func checkThresholds(_ metrics: PerformanceMetrics) {
 if metrics.cpuUsage > alertThreshold {
 for watchdog in watchdogs {
 watchdog.thresholdExceeded(metrics)
 }
 }
 }

 private func hostInfo() -> (cpuUsage: Double, loadAverage: Double) {
 var info = host_basic_info()
 var size = UInt32(MemoryLayout<host_basic_info>.size)

 var kr = withUnsafeMutablePointer(to: &info) { ptr in
 host_info(host_t, HOST_BASIC_INFO, ptr, &size)
 }

 if kr == KERN_SUCCESS {
 let cpuInfo = host_cpu_load_info_t.allocate(capacity: 1)
 var cpuSize = UInt32(MemoryLayout<host_cpu_load_info>.size)

 let kr2 = withUnsafeMutablePointer(to: &cpuInfo.pointee) { ptr in
 host_statistics(host_t, HOST_CPU_LOAD_INFO, ptr, &cpuSize)
 }

 if kr2 == KERN_SUCCESS {
 let user = Double(cpuInfo.pointee.cpu_ticks.0)
 let system = Double(cpuInfo.pointee.cpu_ticks.1)
 let idle = Double(cpuInfo.pointee.cpu_ticks.2)
 let nice = Double(cpuInfo.pointee.cpu_ticks.3)
 let total = user + system + idle + nice
 let usage = total > 0 ? (user + system + nice) / total * 100.0 : 0
 cpuInfo.deallocate()
 return (usage, 0)
 }

 cpuInfo.deallocate()
 }

 return (0, 0)
 }

 private func memoryInfo() -> (used: UInt64, peak: UInt64) {
 var info = task_basic_info()
 var size = UInt32(MemoryLayout<task_basic_info>.size)

 let kr = withUnsafeMutablePointer(to: &info) { ptr in
 task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), ptr, &size)
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
 // Could trigger notification or pause agent work
 }
}

// MARK: - Logger

public struct LoggerWrapper {
 public static func log(level: OSLogType, message: String) {
 let log = OSLog(subsystem: "ai.bridgemind.one", category: "app")
 os_log("%{public}@", log: log, type: level, message)
 }
}
