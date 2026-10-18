import Compression
import CryptoKit
import Foundation

/// Downloads a file. The live implementation is URLSession; tests serve local files.
protocol PackDownloading: Sendable {
    /// `progress` is called with the bytes received so far; it may be kept for the length of the download.
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
}

/// URLSession downloads with byte progress and resume: an interrupted download leaves `<destination>.resume`
/// (URLSession resume data) and the next attempt continues from there ("resumes, never restarts", P7 S0g).
struct URLSessionPackDownloader: PackDownloading {
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let resumeFile = URL(fileURLWithPath: destination.path + ".resume")
        let delegate = DownloadDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeFile) {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }
        try? FileManager.default.removeItem(at: resumeFile)
        let temp: URL
        do {
            // `progress` is escaping: the session's delegate keeps it until the session is invalidated, after this
            // returns (withoutActuallyEscaping trapped on the device, 18 Oct).
            temp = try await withTaskCancellationHandler {
                try await delegate.run(task, progress: progress)
            } onCancel: {
                task.cancel(byProducingResumeData: { _ in })
            }
        } catch {
            if let data = (error as? URLError)?.downloadTaskResumeData { try? data.write(to: resumeFile) }
            throw error
        }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }
}

/// Bridges one download task's delegate callbacks to async/await.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: (@Sendable (Int64) -> Void)?
    private var file: URL?

    func run(_ task: URLSessionDownloadTask, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            lock.withLock { continuation = c; onProgress = progress }
            task.resume()
        }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite _: Int64) {
        let p = lock.withLock { onProgress }
        p?(totalBytesWritten)
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns: move it somewhere we own first.
        let keep = FileManager.default.temporaryDirectory.appending(path: "velix-dl-\(UUID().uuidString)")
        do { try FileManager.default.moveItem(at: location, to: keep); lock.withLock { file = keep } } catch {}
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (c, f) = lock.withLock { () -> (CheckedContinuation<URL, Error>?, URL?) in
            defer { continuation = nil }
            return (continuation, file)
        }
        if let error { c?.resume(throwing: error) } else if let f { c?.resume(returning: f) } else {
            c?.resume(throwing: URLError(.cannotCreateFile))
        }
    }
}

/// An installed pack: `RegionPack/versions/<version>/` with the unpacked files and its manifest.
struct InstalledRegionPack: Equatable, Sendable {
    let directory: URL
    let manifest: RegionPackManifest

    func file(_ role: RegionPackManifest.File.Role) throws -> URL {
        guard let f = manifest.file(role) else { throw RegionPackError.missingFile(role.rawValue) }
        return directory.appending(path: f.name)
    }
}

/// Installs a region pack: download each asset → check sha256 → unpack xz → check unpacked sha256,
/// all in `staging/<version>/`; then switch `current` to the new version and remove the old one.
/// A failure at any step leaves the installed pack untouched. Finished files stay in staging and an interrupted
/// download keeps its resume data, so the next attempt picks up where this one stopped.
struct RegionPackInstaller: Sendable {
    let root: URL
    let downloader: PackDownloading

    init(root: URL = RegionPack.directory, downloader: PackDownloading = URLSessionPackDownloader()) {
        self.root = root
        self.downloader = downloader
    }

    /// - Parameter manifest: URL of `manifest.json`; assets are fetched from the same folder (release download URL).
    @discardableResult
    func install(manifest manifestURL: URL, progress: @escaping @Sendable (Double) -> Void = { _ in })
        async throws -> InstalledRegionPack
    {
        let fm = FileManager.default
        let stagingRoot = root.appending(path: "staging", directoryHint: .isDirectory)
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let manifestFile = stagingRoot.appending(path: "manifest-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: manifestFile) }
        try await downloader.download(manifestURL, to: manifestFile) { _ in }
        let manifest = try RegionPackManifest.decode(Data(contentsOf: manifestFile))
        // Staging for this version only: leftovers of other versions can't be resumed.
        for old in (try? fm.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent != manifest.version && !old.lastPathComponent.hasPrefix("manifest-") {
            try? fm.removeItem(at: old)
        }
        let staging = stagingRoot.appending(path: manifest.version, directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let stagedManifest = staging.appending(path: "manifest.json")
        try? fm.removeItem(at: stagedManifest)
        try fm.copyItem(at: manifestFile, to: stagedManifest)

        let base = manifestURL.deletingLastPathComponent()
        let total = Double(max(manifest.downloadBytes, 1))
        var done: Int64 = 0
        for file in manifest.files {
            let unpacked = staging.appending(path: file.name)
            if (try? Self.verify(unpacked, bytes: file.unpackedBytes, sha256: file.unpackedSha256, label: file.name)) != nil {
                done += file.bytes                       // finished by an earlier attempt
                progress(Double(done) / total)
                continue
            }
            let asset = staging.appending(path: file.asset)
            let before = done
            try await downloader.download(base.appending(path: file.asset), to: asset) { bytes in
                progress(Double(before + bytes) / total)
            }
            done += file.bytes
            do {
                try Self.verify(asset, bytes: file.bytes, sha256: file.sha256, label: file.asset)
            } catch {
                try? fm.removeItem(at: asset)            // corrupt: never resume from it
                throw error
            }
            try Self.decompressXZ(asset, to: unpacked)
            try fm.removeItem(at: asset)
            try Self.verify(unpacked, bytes: file.unpackedBytes, sha256: file.unpackedSha256, label: file.name)
        }
        let versions = root.appending(path: "versions", directoryHint: .isDirectory)
        try fm.createDirectory(at: versions, withIntermediateDirectories: true)
        let target = versions.appending(path: manifest.version, directoryHint: .isDirectory)
        let previous = Self.current(root: root)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: staging, to: target)
        try Self.writeCurrent(manifest.version, root: root)
        if let previous, previous.directory.standardizedFileURL != target.standardizedFileURL {
            try? fm.removeItem(at: previous.directory)
        }
        progress(1)
        return InstalledRegionPack(directory: target, manifest: manifest)
    }

    /// The installed pack `current` points to, if any.
    static func current(root: URL = RegionPack.directory) -> InstalledRegionPack? {
        guard let version = try? String(contentsOf: root.appending(path: "current"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty
        else { return nil }
        let dir = root.appending(path: "versions").appending(path: version, directoryHint: .isDirectory)
        guard let data = try? Data(contentsOf: dir.appending(path: "manifest.json")),
              let manifest = try? RegionPackManifest.decode(data)
        else { return nil }
        return InstalledRegionPack(directory: dir, manifest: manifest)
    }

    /// Atomic: write a temp file, then replace `current` in one rename.
    private static func writeCurrent(_ version: String, root: URL) throws {
        let tmp = root.appending(path: "current.\(UUID().uuidString)")
        try Data(version.utf8).write(to: tmp)
        let current = root.appending(path: "current")
        if FileManager.default.fileExists(atPath: current.path) {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: current)
        }
    }

    private static func verify(_ url: URL, bytes: Int64, sha256 expected: String, label: String) throws {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
        guard size == bytes else { throw RegionPackError.sizeMismatch(label) }
        guard try sha256Hex(url) == expected else { throw RegionPackError.checksumMismatch(label) }
    }

    static func sha256Hex(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: xz (Compression framework: COMPRESSION_LZMA reads and writes the xz container)

    /// Streams `source` (.xz) into `destination` without holding the file in memory.
    static func decompressXZ(_ source: URL, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var failed = false
        let filter = try OutputFilter(.decompress, using: .lzma) { data in
            if let data { do { try output.write(contentsOf: data) } catch { failed = true } }
        }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try filter.write(chunk)
        }
        try filter.finalize()
        if failed { throw RegionPackError.decompression(source.lastPathComponent) }
    }

    /// Used by tests to build fixtures with the same codec the app reads.
    static func compressXZ(_ data: Data) throws -> Data {
        var out = Data()
        let filter = try OutputFilter(.compress, using: .lzma) { chunk in if let chunk { out.append(chunk) } }
        try filter.write(data)
        try filter.finalize()
        return out
    }
}
