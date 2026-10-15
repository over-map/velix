import Foundation

/// A route's elevation profile, smoothed so that only sustained slopes count.
///
/// Valhalla's per-edge grades come from the pack's DEM (Copernicus GLO-30), a surface model that includes buildings
/// and trees: in a dense city a 30 m pixel can be a roof, which gives narrow streets fake 8–15 % "slopes". The
/// profile takes, at every 25 m, the median of the edges' mean elevations within ±250 m (removes spikes), and
/// measures grades over 300 m windows. Calibrated on the M3 golden trips (docs/DECISIONS.md): flat central Milan
/// stays ≤ 5 % even on the terrain model (GEDTM30 keeps ±15–25 m bumps in dense blocks), Bergamo Alta reads 7.3 %.
/// Short steep ramps (< 300 m) are not detected with 30 m DEMs.
struct ElevationProfile: Equatable, Sendable {
    static let step = 25.0
    static let medianRadius = 250.0  // metres either side
    static let gradeWindow = 12      // samples (300 m)

    /// Smoothed elevation every `step` metres from the start.
    let elevations: [Double]

    init(edges: [RouteEdge]) {
        var points: [(d: Double, e: Double)] = []
        var d = 0.0
        for e in edges {
            if let m = e.meanElevation { points.append((d + e.meters / 2, m)) }
            d += e.meters
        }
        guard points.count >= 2, d > 0 else { elevations = []; return }
        let samples = Int(d / Self.step) + 1
        var lo = 0, hi = 0
        var out: [Double] = []
        out.reserveCapacity(samples)
        for i in 0 ..< samples {
            let x = Double(i) * Self.step
            while lo < points.count - 1, points[lo].d < x - Self.medianRadius { lo += 1 }
            while hi < points.count - 1, points[hi + 1].d <= x + Self.medianRadius { hi += 1 }
            let window = points[lo ... max(lo, hi)].map(\.e).sorted()
            out.append(window[window.count / 2])
        }
        elevations = out
    }

    /// Grade (%) of the 300 m window starting at each sample.
    var grades: [Double] {
        guard elevations.count > Self.gradeWindow else { return [] }
        return (0 ..< elevations.count - Self.gradeWindow).map {
            (elevations[$0 + Self.gradeWindow] - elevations[$0]) / (Double(Self.gradeWindow) * Self.step) * 100
        }
    }

    var maxGrade: Double { grades.map(abs).max() ?? 0 }

    var climb: Double {
        zip(elevations, elevations.dropFirst()).reduce(0) { $0 + max(0, $1.1 - $1.0) }
    }

    /// Stretches steeper than `threshold` % (climb > 0, descent < 0), at least `minLength` long: (start, length, worst %).
    func stretches(steeperThan threshold: Double, climb: Bool, minLength: Double) -> [(start: Double, length: Double, worst: Double)] {
        var out: [(Double, Double, Double)] = []
        var start: Int?, worst = 0.0
        let g = grades
        for i in 0 ... g.count {
            let v = i < g.count ? (climb ? g[i] : -g[i]) : 0
            if i < g.count, v > threshold {
                if start == nil { start = i; worst = 0 }
                worst = max(worst, v)
            } else if let s = start {
                let length = Double(i - s + Self.gradeWindow) * Self.step
                if length >= minLength { out.append((Double(s) * Self.step, length, worst)) }
                start = nil
            }
        }
        return out
    }
}
