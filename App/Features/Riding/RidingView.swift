import SwiftUI

/// S4 Riding (P5): the ride on the Velix map, following the rider, with the controls and the one-thing-at-a-time
/// cards. Reads the ride from ``RideSession``; ``RidingScreen`` draws it (and the snapshot tests).
struct RidingView: View {
    @Bindable var session: RideSession
    @Bindable var app: AppModel
    /// Bike + transit (P6): the stages on top of the ride.
    var transit: TransitRide?
    @State private var camera = RideCamera()
    @State private var motion = MapCameraMotion.track
    /// The camera while panned: held so the map stays where the rider put it.
    @State private var held: MapCamera?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = screen
        RidingScreen(state: state, camera: camera, voice: session.voice.mode, mapStyle: MapStyleKind(app.mapStyle),
                     bikeLanes: app.bikeLanes, transitLines: app.transitLines, target: target(state), motion: motion,
                     onVoice: { session.voice.cycle() },
                     onView: { change { camera.cycleView() } },
                     onOverview: { change { camera.toggleOverview(at: Date()) } },
                     onRecenter: { change { camera.recenter() } },
                     onPan: { if !camera.isPanned { held = target(state) }; camera.userPanned(at: Date()) },
                     onEnd: { if let transit { transit.end() } else { session.end() } })
            .onChange(of: session.here) { motion = .track }
            .task {
                // Overview and pan go back to follow after 10 s (P5 S4d, S4j).
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    var next = camera
                    if next.tick(at: Date()) { change { camera = next } }
                }
            }
    }

    /// The ride, with the bike + transit stages on top when it is one (P6).
    private var screen: RideScreenState {
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer { Perf.add("screen", CACurrentMediaTime() - t0) }
        #endif
        var state = session.screen(chevron: camera.drawsRider, now: AppClock.now)
        transit?.decorate(&state)
        return state
    }

    /// A tap on a control: the camera moves at the view-change pace (a cut with Reduce Motion), then tracks again.
    private func change(_ update: () -> Void) {
        motion = .viewMode(reduceMotion: reduceMotion)
        update()
    }

    private func target(_ state: RideScreenState) -> MapCamera {
        if camera.isPanned, let held { return held }
        guard let rider = state.rider else { return MapCamera(center: session.destination.location, zoom: 15) }
        return camera.follow(at: rider, course: state.course)
    }
}

/// The S4 screen for a ``RideScreenState`` (P5 frames: banner, control stack, hazard card or notice, ETA bar).
struct RidingScreen: View {
    let state: RideScreenState
    let camera: RideCamera
    let voice: VoiceMode
    var mapStyle: MapStyleKind = .standard
    var bikeLanes = false
    var transitLines = false
    var target: MapCamera?
    var motion: MapCameraMotion = .track
    var onVoice: () -> Void = {}
    var onView: () -> Void = {}
    var onOverview: () -> Void = {}
    var onRecenter: () -> Void = {}
    var onPan: () -> Void = {}
    var onEnd: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.liveMap) private var liveMap
    @State private var confirmEnd = false
    /// Measured: how much the on-train sheet and the ETA bar cover (the fit and the map's ⓘ follow them).
    @State private var trainCard: CGFloat?
    @State private var etaBar: CGFloat?

    /// The overview fits the rest of the trip between the banner and the ETA bar (design/p4/maps.js rOver: 250 / 120,
    /// plus 20 so the ends clear them; VelixMap adds 40 all round).
    static let overviewInsets = UIEdgeInsets(top: 230, left: 0, bottom: 100, right: 0)
    /// P6 S5d map: top 110, bottom 470 (VelixMap adds 40).
    static let trainInsets = UIEdgeInsets(top: 70, left: 0, bottom: 430, right: 0)
    /// The trip between the strip and the sheet, the sheet as tall as it is now (P6 S5d's 430 until measured).
    private var trainInsets: UIEdgeInsets {
        var i = Self.trainInsets
        if let trainCard { i.bottom = trainCard }
        return i
    }

    /// The weak-GPS halo around the rider (P5 S4h).
    static let haloSize: CGFloat = 116

    var body: some View {
        if let train = state.onTrain { onTrain(train) } else { riding }
    }

    /// P6 S5d: the strip on top, the countdown sheet at the bottom, the whole trip on the map.
    private func onTrain(_ card: OnTrainCard) -> some View {
        ZStack {
            map.ignoresSafeArea()
            VStack(spacing: 0) {
                if let stage = state.stage {
                    stage.padding(12)
                        .background(Color.velix.surface, in: RoundedRectangle(cornerRadius: 20))
                        .velixElevation(VelixElevations.e1, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 10)
                }
                Spacer()
            }
            VStack(alignment: .trailing, spacing: 10) {
                Spacer()
                // Ending the ride on the train too (Filippo, 30 Oct): the same End as the ETA bar's, above the sheet.
                Button { confirmEnd = true } label: {
                    Text("End ride").velixType(.button).foregroundStyle(Color.velix.dangerInk)
                        .padding(.horizontal, 20).frame(height: 48)
                        .background(Color.velix.danger, in: Capsule())
                        .velixElevation(VelixElevations.e1, in: Capsule())
                }
                .buttonStyle(VelixPressStyle())
                .padding(.trailing, 16)
                card.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { trainCard = VelixMap.covered(fromTop: $0) }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .dynamicTypeSize(...DynamicTypeSize.velixRidingCap)
        .confirmationDialog("End this ride?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End ride", role: .destructive, action: onEnd)
            Button("Keep riding", role: .cancel) {}
        }
    }

    private var riding: some View {
        ZStack {
            map.ignoresSafeArea()
            rider.ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                top
                HStack(alignment: .top) {
                    Spacer()
                    VStack(spacing: 12) {
                        MapControlStack(voice: voice.control, view: camera.view, overview: camera.isOverview,
                                        onVoice: onVoice, onView: onView, onOverview: onOverview)
                        if camera.isPanned { RecenterButton(riding: true, action: onRecenter) }
                    }
                }
                .padding(.top, 18)
                Spacer(minLength: 0)
                bottomCard.padding(.bottom, 4)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 108 - 34)     // the ETA bar's height above the home indicator
            VStack {
                Spacer()
                EtaBar(state: state.eta) { confirmEnd = true }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { etaBar = VelixMap.covered(fromTop: $0) }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .dynamicTypeSize(...DynamicTypeSize.velixRidingCap)
        .confirmationDialog("End this ride?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End ride", role: .destructive, action: onEnd)
            Button("Keep riding", role: .cancel) {}
        }
    }

    // MARK: Map

    @ViewBuilder private var map: some View {
        if liveMap, let target {
            // The overview, and the train stage (P6 S5d: the whole trip between the strip and the sheet), fit the trip.
            let train = state.onTrain != nil
            VelixMap(style: mapStyle, mode: scheme == .dark ? .night : .day, bikeLanes: bikeLanes, transitLines: transitLines,
                     route: state.map, camera: target,
                     insets: train ? trainInsets : camera.isOverview ? Self.overviewInsets : .zero,
                     fit: (camera.isOverview || train) && state.ahead.count > 1 ? state.ahead : nil, motion: motion,
                     riding: true, coveredBottom: train ? nil : etaBar, onUserPan: onPan)
        } else {
            Color.velix.surface2
        }
    }

    /// The rider at the camera's anchor while following: the P3 chevron (2D, 3D) or the dot and cone (North up), and
    /// the weak-GPS halo.
    @ViewBuilder private var rider: some View {
        if camera.isFollowing, let target {
            GeometryReader { g in
                ZStack {
                    if state.weakGPS {
                        Circle().fill(Color.velix.accent.opacity(0.16))
                            .overlay { Circle().strokeBorder(Color.velix.casing.opacity(0.35), lineWidth: 2) }
                            .frame(width: Self.haloSize, height: Self.haloSize)
                    }
                    // The overview's dot in every view (Filippo, 30 Oct: no chevron). Heading-up views turn the map, so
                    // the cone points up; North up turns the cone.
                    RiderPuck(course: camera.showsChevron ? 0 : state.course)
                }
                .position(x: g.size.width / 2, y: g.size.height * target.anchor)
            }
        }
    }

    // MARK: Cards

    @ViewBuilder private var top: some View {
        switch state.top {
        case .rerouting:
            RerouteBanner()
        case let .turn(turn, pill, pillDistance):
            ManeuverBanner(maneuver: turn.maneuver, distance: RideSession.distance(turn.meters), street: turn.street,
                           then: turn.then.map { ($0.maneuver, $0.street) }, roadType: pill, roadTypeDistance: pillDistance,
                           stage: state.stage)
        }
    }

    /// One card above the ETA bar: the weak-GPS notice, else the next hazard (P5 S4h: the card steps aside); none in
/// the overview.
    @ViewBuilder private var bottomCard: some View {
        if camera.isOverview {
            EmptyView()     // S4d: the whole trip, every hazard on the map, no card
        } else if let n = state.notice {
            TransitNotice(kind: n.kind, title: n.title, message: n.message)   // P6: the hazard card's slot, for 8 s
        } else if state.weakGPS {
            NoticeBanner.weakGPS()
        } else if let h = state.hazard {
            NextHazardCard(type: h.type, advice: h.advice, distance: h.distance, approaching: h.approaching)
                .animation(VelixMotions.hazardApproach.animation, value: h.approaching)
        }
    }
}

/// The follow puck (P3 render.js `F.follow`): an accent chevron with a white halo and an ink outline, pointing up.
struct RiderChevron: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.25)).frame(width: 34, height: 12).offset(y: 10)
            ChevronShape().stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineJoin: .round))
            ChevronShape().stroke(Color.velix.casing, style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
            ChevronShape().fill(Color.velix.accent)
        }
        .frame(width: 36, height: 40)
        .offset(y: -4)          // P3's origin (the rider) is at y 0 of −24…16, 4 pt below the box's middle
        .accessibilityHidden(true)
    }

    /// (0, −24) → (18, 16) → (0, 7) → (−18, 16), on a 36 × 40 box.
    struct ChevronShape: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 31 / 40))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// The North-up rider (P3 puck, z16+: cone 46): the dot stays at the anchor and the cone turns with the course,
/// gliding over the fix interval the shortest way round.
struct RiderPuck: View {
    let course: Double
    @State private var angle: Double?

    var body: some View {
        ZStack {
            Cone().fill(Color.velix.accent.opacity(0.42)).frame(width: 92, height: 92)
                .rotationEffect(.degrees(angle ?? course))
            Circle().fill(Color.white).frame(width: 24, height: 24)
            Circle().fill(Color.velix.accent).frame(width: 20, height: 20)
                .overlay { Circle().strokeBorder(Color.velix.casing, lineWidth: 3) }
            NavigationArrow().fill(Color.velix.accentInk).frame(width: 8, height: 9).rotationEffect(.degrees(angle ?? course))
        }
        .accessibilityHidden(true)
        .onChange(of: course) { _, new in
            let from = angle ?? new
            let delta = (new - from).truncatingRemainder(dividingBy: 360)
            let shortest = delta > 180 ? delta - 360 : delta < -180 ? delta + 360 : delta
            withAnimation(.linear(duration: 1)) { angle = from + shortest }
        }
    }

    /// A 57° wedge from the centre, pointing up (MapImages.puck: ±0.5 rad).
    struct Cone: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: r.midX, y: r.midY)
            p.move(to: c)
            p.addArc(center: c, radius: r.width / 2, startAngle: .radians(-.pi / 2 - 0.5), endAngle: .radians(-.pi / 2 + 0.5), clockwise: false)
            p.closeSubpath()
            return p
        }
    }
}

extension VoiceMode {
    var control: MapControlStack.Voice {
        switch self { case .all: .all; case .alerts: .alerts; case .mute: .mute }
    }
}
