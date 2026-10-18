import Foundation
import Network
import Observation

/// The region pack as the screens see it (S0e–g, S1d, S8 offline map): installed, downloading with bytes, failed.
@MainActor
@Observable
final class PackService {
    enum State: Equatable {
        case none
        case checking
        case downloading(received: Int64, total: Int64)
        case failed(received: Int64, total: Int64)
        case ready(RegionPackManifest)
    }

    private(set) var state: State = .none
    /// On mobile data (S0e "Switch to Wi-Fi…").
    private(set) var isExpensive = false
    /// Region name for copy ("Downloading Lombardy").
    private(set) var regionName = "Lombardy"

    var onInstalled: () -> Void = {}

    private let installer: RegionPackInstaller
    private let catalog: () async throws -> URL?
    private let monitor = NWPathMonitor()
    private var task: Task<Void, Never>?

    init(installer: RegionPackInstaller = RegionPackInstaller(),
         catalog: @escaping () async throws -> URL? = { try await RegionPackCatalog.latestManifestURL() }) {
        self.installer = installer
        self.catalog = catalog
        if let current = RegionPackInstaller.current(root: installer.root) {
            state = .ready(current.manifest)
            regionName = current.manifest.name
        } else if RegionPack.tileExtract != nil {
            // Side-loaded (debug): routes work, nothing to download.
            state = .ready(RegionPackManifest.sideloaded)
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            Task { @MainActor in self?.isExpensive = expensive }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    var isReady: Bool { if case .ready = state { true } else { false } }
    var isDownloading: Bool { if case .downloading = state { true } else { false } }

    /// Fraction for progress bars.
    var fraction: Double {
        switch state {
        case let .downloading(r, t), let .failed(r, t): t > 0 ? Double(r) / Double(t) : 0
        case .ready: 1
        default: 0
        }
    }

    private func progress(_ fraction: Double, total: Int64) {
        guard case .downloading = state else { return }
        state = .downloading(received: Int64(fraction * Double(total)), total: total)
    }

    #if DEBUG
    func setForTesting(_ state: State, expensive: Bool = false) {
        self.state = state
        isExpensive = expensive
    }
    #endif

    /// Install the latest release; resumes an interrupted download.
    func install() {
        guard task == nil else { return }
        let previous = state
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            self.state = .checking
            do {
                guard let url = try await self.catalog() else { self.state = previous; return }
                let latest = try? RegionPackManifest.decode(await URLSession.shared.data(from: url).0)
                let total = latest?.downloadBytes ?? 0
                if let latest { self.regionName = latest.name }
                self.state = .downloading(received: 0, total: total)
                let installed = try await self.installer.install(manifest: url) { fraction in
                    Task { @MainActor in self.progress(fraction, total: total) }
                }
                self.state = .ready(installed.manifest)
                self.onInstalled()
            } catch {
                if case let .downloading(r, t) = self.state { self.state = .failed(received: r, total: t) }
                else { self.state = previous == .checking ? .none : previous }
            }
        }
    }
}

extension RegionPackManifest {
    /// Stand-in for a side-loaded pack (debug), so screens treat it as ready.
    static let sideloaded = RegionPackManifest(schema: 1, pack: "lombardy", name: "Lombardy", version: "side-loaded",
                                               built: "", valhalla: "", bbox: [8.49785, 44.67991, 11.42765, 46.63535],
                                               files: [], downloadBytes: 0, unpackedBytes: 0, budgetBytes: 0, sources: [])

    /// Rough region check until the pack ships its polygon to the app: inside the bbox.
    func contains(_ p: LatLon) -> Bool {
        bbox.count == 4 && p.lon >= bbox[0] && p.lat >= bbox[1] && p.lon <= bbox[2] && p.lat <= bbox[3]
    }
}
