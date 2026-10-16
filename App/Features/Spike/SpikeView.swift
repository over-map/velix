#if DEBUG
@preconcurrency import FerrostarCore
import FerrostarMapLibreUI
import FerrostarSwiftUI
import MapLibreSwiftUI
import SwiftUI

/// M1 spike screen (debug builds only). Uses Ferrostar's stock navigation UI on purpose:
/// the Velix riding UI (HANDOFF S4) is built in M7.
struct SpikeView: View {
    @State private var model = SpikeModel()
    @State private var showLog = false

    /// OpenFreeMap Liberty (OpenMapTiles schema, no key). Velix styles come in M5.
    private let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    var body: some View {
        DynamicallyOrientingNavigationView(
            styleURL: styleURL,
            camera: $model.camera,
            navigationState: model.navigationState,
            isMuted: model.core?.spokenInstructionObserver.isMuted ?? false,
            onTapMute: { model.core?.spokenInstructionObserver.toggleMute() },
            onTapExit: { model.stopRide() }
        )
        .safeAreaInset(edge: .bottom) {
            if !model.isNavigating { controls }
        }
        .task {
            await model.loadEngine()
            // Launch arguments let the spike run unattended on a device (devicectl process launch … -m1-benchmark).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-m2-install-pack") { await model.installLatestPack() }
            if args.contains("-m1-benchmark") { await model.runBenchmark() }
            if args.contains("-m3-plan") { await model.runPlannerBenchmark() }
            if args.contains("-m1-simride") {
                model.locationSource = .simulated
                await model.startRide(to: SpikeTrip.politecnico, name: "Politecnico")
            }
        }
        .sheet(isPresented: $showLog) {
            ScrollView { Text(model.metricsLog()).font(.system(.caption2, design: .monospaced)).padding() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("M1 spike").velixType(.bodyBold)
            Text(model.status).font(.footnote)
            ForEach(model.results, id: \.self) { Text($0).font(.caption2) }
            Picker("Location", selection: $model.locationSource) {
                ForEach(SpikeModel.LocationSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Benchmark") { Task { await model.runBenchmark() } }
                Button("Ride → Politecnico") { Task { await model.startRide(to: SpikeTrip.politecnico, name: "Politecnico") } }
                Button("Pack") { Task { await model.installLatestPack() } }
                Button("Log") { showLog = true }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
    }
}
#endif
