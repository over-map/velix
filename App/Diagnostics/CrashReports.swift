import Foundation
import MetricKit

/// Crash, hang and resource-exception reports from iOS (MetricKit), kept on the phone in `Documents/diagnostics/` for
/// the M7 review (`tools/ride-report`). iOS hands them over on a later launch, up to a day after the event.
final class CrashReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReports()
    static let directory = URL.documentsDirectory.appending(path: "diagnostics")

    func start() {
        MXMetricManager.shared.add(self)
        // Anything delivered while the app wasn't listening.
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
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
