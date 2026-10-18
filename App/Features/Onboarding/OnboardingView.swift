import SwiftUI
import UIKit

/// S0 First launch, steps 1–2 (P7 §04): location, then ride type. Step 3 (download) is ``DownloadSheet`` over the map.
struct OnboardingView: View {
    let app: AppModel
    var onDone: () -> Void
    @State private var step: Int
    @State private var skippedLocation = false
    @State private var rideType: RideType = .city

    init(app: AppModel, step: Int = 0, onDone: @escaping () -> Void) {
        self.app = app
        self.onDone = onDone
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageDots(step: step).frame(maxWidth: .infinity).padding(.top, CGFloat.velix.xs)
            if step == 0 { location } else { rideTypeStep }
        }
        .padding(.horizontal, CGFloat.velix.m)
        .padding(.bottom, CGFloat.velix.xs)
        .background(Color.velix.canvas)
        .onChange(of: app.location.access) { _, access in if access == .allowed, step == 0 { step = 1 } }
        .onAppear { if app.location.access == .allowed { step = 1 } }
    }

    @ViewBuilder private var location: some View {
        let denied = app.location.access == .denied
        Spacer()
        VelixIconView(denied ? .locateOff : .locateFixed, size: 40)
            .foregroundStyle(denied ? Color.velix.ink : Color.velix.accentInk)
            .frame(width: 84, height: 84)
            .background(denied ? Color.velix.surface2 : Color.velix.accent, in: RoundedRectangle(cornerRadius: 18))
            .overlay { if !denied { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.velix.casing, lineWidth: 2) } }
            .padding(.bottom, CGFloat.velix.l)
        Text(denied ? "Location is off" : "Start from\nwhere you are").velixType(.display).foregroundStyle(Color.velix.ink)
            .padding(.bottom, CGFloat.velix.s)
        Text(denied ? "You can still search and plan from any place, but Velix can’t follow you while riding. Turn it on in Settings any time."
                    : "Velix uses your location to plan routes from here and to follow you while you ride. It never leaves this phone.")
            .velixType(.body).foregroundStyle(Color.velix.ink2)
        Spacer()
        if denied {
            PrimaryButton(title: "Open Settings", kind: .ink) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            InlineLink(title: "Continue without") { step = 1 }.frame(maxWidth: .infinity).padding(.top, CGFloat.velix.xs)
        } else {
            PrimaryButton(title: "Allow location", casing: true) { app.location.requestAccess() }
        }
    }

    @ViewBuilder private var rideTypeStep: some View {
        Spacer()
        Text("What do you\nusually ride?").velixType(.display).foregroundStyle(Color.velix.ink).padding(.bottom, CGFloat.velix.m)
        RideTypeGrid(selected: $rideType, minHeight: 68)
        Text("Change it any time with the chip on the Ride map.").velixType(.footnote).foregroundStyle(Color.velix.ink2)
            .padding(.top, CGFloat.velix.s)
        Spacer()
        PrimaryButton(title: "Continue", casing: true) {
            app.state.rideType = rideType
            onDone()
        }
    }
}

/// Onboarding page dots: current 22 × 8 ink, others 8 × 8 line.
struct PageDots: View {
    let step: Int
    var count = 3
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { i in
                Capsule().fill(i == step ? Color.velix.ink : Color.velix.line).frame(width: i == step ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(count)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// S0e–g: Lombardy downloading / ready / paused, over the live map.
struct DownloadSheet: View {
    let pack: PackService
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            Capsule().fill(Color.velix.line).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            PageDots(step: 2).frame(maxWidth: .infinity)
            switch pack.state {
            case .ready: ready
            case let .failed(r, t): failed(r, t)
            case let .downloading(r, t): downloading(r, t)
            default: downloading(0, 0)
            }
        }
        .padding(EdgeInsets(top: CGFloat.velix.xs, leading: CGFloat.velix.m, bottom: CGFloat.velix.xs, trailing: CGFloat.velix.m))
        .background(Color.velix.surface, in: UnevenRoundedRectangle(topLeadingRadius: CGFloat.velix.radius.sheet, topTrailingRadius: CGFloat.velix.radius.sheet))
        .velixElevation(VelixElevations.e3, in: RoundedRectangle(cornerRadius: CGFloat.velix.radius.sheet))
        .background(alignment: .bottom) { Color.velix.surface.frame(height: 60).offset(y: 50) }
        .transition(.move(edge: .bottom))
    }

    private func downloading(_ r: Int64, _ t: Int64) -> some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            Text("Downloading \(pack.regionName)").velixType(.title2).foregroundStyle(Color.velix.ink)
            Text("Routes and the map work offline once it’s done.").velixType(.callout).foregroundStyle(Color.velix.ink2)
            progress(r, t, colour: Color.velix.ink)
            if pack.isExpensive, t > r {
                HStack(alignment: .top, spacing: CGFloat.velix.xs) {
                    VelixIconView(.wifi, size: 18)
                    (Text("You’re on mobile data. ").bold() + Text("Switch to Wi-Fi to save \((t - r) / 1_000_000) MB more of your plan."))
                        .velixType(VelixType.body.sized(13, lineHeight: 17))
                }
                .foregroundStyle(Color.velix.warningInk)
                .padding(CGFloat.velix.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.velix.warningSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            PrimaryButton(title: "Explore the map", casing: true, action: onClose)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            HStack(spacing: CGFloat.velix.xs) {
                VelixIconView(.circleCheck, size: 26).foregroundStyle(Color.velix.success)
                Text("\(pack.regionName) is ready").velixType(.title2).foregroundStyle(Color.velix.ink)
            }
            if case let .ready(m) = pack.state, m.downloadBytes > 0 {
                Text("\(m.downloadBytes / 1_000_000) MB. Routes work anywhere in \(pack.regionName), even without signal.")
                    .velixType(.callout).foregroundStyle(Color.velix.ink2)
            }
            PrimaryButton(title: "Start riding", casing: true, action: onClose)
        }
    }

    private func failed(_ r: Int64, _ t: Int64) -> some View {
        VStack(alignment: .leading, spacing: CGFloat.velix.s) {
            Text("Download paused").velixType(.title2).foregroundStyle(Color.velix.ink)
            Text("The connection dropped at \(r / 1_000_000) MB. Velix picks up from there.").velixType(.callout).foregroundStyle(Color.velix.ink2)
            progress(r, t, colour: Color.velix.ink3)
            PrimaryButton(title: "Try again", icon: .rotateCw, kind: .ink) { pack.install() }
            InlineLink(title: "Explore the map", action: onClose).frame(maxWidth: .infinity)
        }
    }

    private func progress(_ r: Int64, _ t: Int64, colour: Color) -> some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                Capsule().fill(Color.velix.surface2)
                    .overlay(alignment: .leading) { Capsule().fill(colour).frame(width: g.size.width * (t > 0 ? Double(r) / Double(t) : 0)) }
            }
            .frame(height: 8)
            HStack {
                Text(t > 0 ? Format.megabytes(r, of: t) : "Checking…")
                Spacer()
                Text(t > 0 ? "\(Int((Double(r) / Double(t) * 100).rounded()))%" : "")
            }
            .velixType(.label).monospacedDigit().foregroundStyle(Color.velix.ink)
        }
        .accessibilityElement()
        .accessibilityLabel("Downloading \(pack.regionName), \(r / 1_000_000) of \(t / 1_000_000) megabytes")
    }
}
