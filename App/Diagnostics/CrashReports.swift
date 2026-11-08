import Foundation
import MetricKit

/// Crash, hang and resource-exception reports from iOS (MetricKit), kept on the phone in `Documents/diagnostics/` for
/// the M7 review (`tools/ride-report`). iOS hands them over on a later launch, up to a day after the event. Daily metrics
/// payloads go next to them as `metrics-<day>.json` (M10).
final class CrashReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReports()
    static let directory = URL.documentsDirectory.appending(path: "diagnostics")

    func start() {
        MXMetricManager.shared.add(self)
        // Anything delivered while the app wasn't listening; written off the launch path (M10).
        Task.detached(priority: .utility) {
            self.didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
            self.didReceive(MXMetricManager.shared.pastPayloads)
        }
    }

    /// M10: iOS's daily metrics (launch-time histogram, hang rate, CPU and GPU time, location and display use), one file a day.
    func didReceive(_ payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        for p in payloads {
            let day = p.timeStampBegin.formatted(.iso8601.year().month().day())
            let url = Self.directory.appending(path: "metrics-\(day).json")
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? p.jsonRepresentation().write(to: url)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        for p in payloads {
            let name = p.timeStampBegin.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "")
            let url = Self.directory.appending(path: "\(name)-\(p.timeStampEnd.timeIntervalSince1970.rounded()).json")
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? p.jsonRepresentation().write(to: url)
        }
    }
}
