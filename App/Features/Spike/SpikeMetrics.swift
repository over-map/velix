#if DEBUG
import Foundation
import os
import UIKit

/// M1 measurements. Appends one JSON object per line to Documents/m1-metrics.jsonl so the
/// log can be pulled off the phone with `devicectl device copy from` after a ride.
final class SpikeMetrics: @unchecked Sendable {
    static let shared = SpikeMetrics()

    let fileURL = URL.documentsDirectory.appending(path: "m1-metrics.jsonl")
    private let queue = DispatchQueue(label: "velix.spike.metrics")
    private let logger = Logger(subsystem: "dev.velix", category: "m1")

    @MainActor
    func log(_ event: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = event
        record["t"] = ISO8601DateFormatter().string(from: .now)
        record["memMB"] = Int(Self.memoryFootprintMB.rounded())
        let battery = UIDevice.current.batteryLevel
        if battery >= 0 { record["batteryPct"] = Int((battery * 100).rounded()) }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        let line = String(decoding: data, as: UTF8.self)
        queue.async { [fileURL, logger] in
            logger.info("\(line, privacy: .public)")
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
                try? handle.close()
            } else {
                try? Data((line + "\n").utf8).write(to: fileURL)
            }
        }
    }

    /// Physical memory footprint, the number Xcode's memory gauge and jetsam use.
    static var memoryFootprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
#endif
