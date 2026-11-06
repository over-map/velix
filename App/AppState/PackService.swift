import Foundation
import Network
import Observation

/// The region packs as the screens see them (S0e–g, S1d, S8 offline map; Filippo, 2 Nov: several regions): the regions
/// on offer (``catalog``), each one installed, downloading with bytes, or failed. `state` and `regionName` are the
/// region in focus: the one downloading, else the active one (``RegionPack/active``).
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

    /// Every region's state (a region missing here is `.none`).
    private(set) var states: [String: State] = [:]
    /// The regions on offer (``RegionPackCatalog``), empty until fetched.
    private(set) var catalog = RegionCatalog(schema: 1, regions: [])
    /// The region whose download runs now, if one does.
    private(set) var downloading: String?
    /// On mobile data (S0e "Switch to Wi-Fi…").
    private(set) var isExpensive = false
    /// Has a connection: outside the downloaded regions the map comes online (Filippo, 5 Nov).
    private(set) var isOnline = true
    /// Tests set the connection; the monitor leaves it.
    private var connectionPinned = false
    /// You → Offline map: Update automatically. Newer packs of the downloaded regions install on Wi-Fi, one at a time.
    var autoUpdate = false { didSet { installUpdates() } }
    /// The running download updates a region that stays usable (its old pack serves until the new one is in).
    private var updating = false
    /// Updates that failed this launch (not retried until the next one).
    private var failedUpdates: Set<String> = []
    /// A download asked for while an update ran: it goes first, the update resumes after it.
    private var queued: String?

    /// Called with the region after a pack installs or is removed.
    var onInstalled: (String) -> Void = { _ in }

    private let base: URL
    private let installerFor: (String) -> RegionPackInstaller
    private let fetchCatalog: () async throws -> RegionCatalog
    private let monitor = NWPathMonitor()
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - base: `RegionPack/` (one folder per region inside).
    ///   - catalog: the regions on offer (tests: a fixed list).
    init(base: URL = RegionPack.directory, downloader: PackDownloading = URLSessionPackDownloader(),
         catalog: @escaping () async throws -> RegionCatalog = { try await RegionPackCatalog.fetch() }) {
        self.base = base
        installerFor = { RegionPackInstaller(root: RegionPack.root($0, base: base), downloader: downloader) }
        fetchCatalog = catalog
        RegionPack.migrateLegacyLayout(base: base)
        for p in RegionPack.installed(base: base) { states[p.manifest.pack] = .ready(p.manifest) }
        if states.isEmpty, RegionPack.tileExtract != nil {
            // Side-loaded (debug): routes work, nothing to download.
            states[RegionPack.active] = .ready(RegionPackManifest.sideloaded)
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive, online = path.status == .satisfied
            Task { @MainActor in
                guard let self, !self.connectionPinned else { return }
                self.isExpensive = expensive
                self.isOnline = online
                self.installUpdates()
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    // MARK: The region in focus (the screens of one region)

    private var focus: String { downloading ?? RegionPack.active }
    var state: State { states[focus] ?? .none }
    var regionName: String { name(of: focus) }

    var isReady: Bool { !installed.isEmpty }
    /// A region is downloading (a background update doesn't count: the screens show nothing for it).
    var isDownloading: Bool { downloading != nil && !updating }

    /// Fraction for progress bars.
    var fraction: Double {
        switch state {
        case let .downloading(r, t), let .failed(r, t): t > 0 ? Double(r) / Double(t) : 0
        case .ready: 1
        default: 0
        }
    }

    // MARK: Regions

    /// The installed regions' manifests, by name.
    var installed: [RegionPackManifest] {
        states.values.compactMap { if case let .ready(m) = $0 { m } else { nil } }.sorted { $0.name < $1.name }
    }

    func state(of region: String) -> State { states[region] ?? .none }
    func isInstalled(_ region: String) -> Bool { if case .ready = states[region] { true } else { false } }

    func name(of region: String) -> String {
        if case let .ready(m) = states[region] { return m.name }
        return catalog.region(region)?.name ?? region.capitalized
    }

    /// An installed region holding the point inside its border.
    func installedRegion(containing p: LatLon) -> RegionPackManifest? { installed.first { $0.contains(p) } }

    /// Some installed pack's routing data reaches the point.
    func covers(_ p: LatLon) -> Bool { installed.contains { $0.covers(p) } }

    /// The region on offer at a point that isn't on the phone (browsing or searching outside: offer its download).
    func offer(at p: LatLon) -> RegionCatalog.Region? {
        guard installedRegion(containing: p) == nil, let r = catalog.region(containing: p), !isInstalled(r.id) else { return nil }
        return r
    }

    #if DEBUG
    func setForTesting(_ state: State, expensive: Bool = false, region: String = "lombardy", online: Bool = true) {
        states[region] = state
        isExpensive = expensive
        isOnline = online
        connectionPinned = true
        if case .downloading = state { downloading = region } else if downloading == region { downloading = nil }
    }

    func setCatalogForTesting(_ c: RegionCatalog) { catalog = c }
    #endif

    func refreshCatalog() async {
        if let c = try? await fetchCatalog(), !c.regions.isEmpty { catalog = c }
        installUpdates()
    }

    /// With Update automatically on and Wi-Fi, install the next newer pack of a downloaded region.
    func installUpdates() {
        guard autoUpdate, isOnline, !isExpensive, task == nil,
              let next = installed.first(where: { hasUpdate($0.pack) && !failedUpdates.contains($0.pack) }) else { return }
        install(next.pack)
    }

    /// Install a region's newest pack (the active region by default: first launch); resumes an interrupted download.
    /// One download at a time.
    func install(_ region: String? = nil) {
        let region = region ?? RegionPack.active
        guard task == nil else {
            // The rider's download goes before a background update (which resumes later from its staged files).
            if updating, downloading != region { queued = region; task?.cancel() }
            return
        }
        let previous = state(of: region)
        let update: Bool = if case .ready = previous { true } else { false }
        downloading = region
        updating = update
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil; self.downloading = nil; self.updating = false
                if let next = self.queued { self.queued = nil; self.install(next) } else { self.installUpdates() }
            }
            if !update { self.states[region] = .checking }
            do {
                if self.catalog.regions.isEmpty { await self.refreshCatalog() }
                guard let entry = self.catalog.region(region) else { self.states[region] = previous; return }
                let total = entry.downloadBytes
                if !update { self.states[region] = .downloading(received: 0, total: total) }
                let installed = try await self.installerFor(region).install(manifest: entry.manifest) { fraction in
                    Task { @MainActor in self.progress(region, fraction, total: total) }
                }
                self.states[region] = .ready(installed.manifest)
                PackTileProtocol.use(RegionPack.mapSources)
                self.onInstalled(region)
            } catch {
                if update {
                    // The installed pack is untouched; a cancelled update (the rider's download first) comes back.
                    self.states[region] = previous
                    if self.queued == nil { self.failedUpdates.insert(region) }
                } else if case let .downloading(r, t) = self.states[region] { self.states[region] = .failed(received: r, total: t) }
                else { self.states[region] = previous == .checking ? .none : previous }
            }
        }
    }

    /// Stop the running download (You → Offline map: Cancel). Its files so far stay, so Retry resumes.
    func cancel(_ region: String) {
        guard downloading == region else { return }
        task?.cancel()
    }

    /// A downloaded region can be removed while another one stays: routes need one (and launch re-downloads it).
    func canRemove(_ region: String) -> Bool {
        isInstalled(region) && downloading != region && installed.count > 1
    }

    /// A newer pack of an installed region is on offer.
    func hasUpdate(_ region: String) -> Bool {
        guard case let .ready(m) = states[region], let r = catalog.region(region) else { return false }
        return r.version > m.version
    }

    /// Remove a downloaded region (You → Offline map), unless it's the last one.
    func delete(_ region: String) {
        guard canRemove(region) else { return }
        try? FileManager.default.removeItem(at: RegionPack.root(region, base: base))
        states[region] = nil
        if RegionPack.active == region, let other = installed.first?.pack { RegionPack.active = other }
        PackTileProtocol.use(RegionPack.mapSources)
        onInstalled(region)
    }

    private func progress(_ region: String, _ fraction: Double, total: Int64) {
        guard case .downloading = states[region] else { return }
        states[region] = .downloading(received: Int64(fraction * Double(total)), total: total)
    }
}

extension RegionPackManifest {
    /// Stand-in for a side-loaded pack (debug), so screens treat it as ready.
    static let sideloaded = RegionPackManifest(schema: 1, pack: "lombardy", name: "Lombardy", version: "side-loaded",
                                               built: "", valhalla: "", bbox: [8.49785, 44.67991, 11.42765, 46.63535],
                                               files: [], downloadBytes: 0, unpackedBytes: 0, budgetBytes: 0, sources: [])
}
