import SwiftUI

// All pet art is drawn with shapes, so there are no image files to add.
// This file is shared with the Home Screen widget.

// MARK: - Basic shapes

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

struct Mouth: Shape {
    var curve: CGFloat
    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.midY + rect.height * curve * 2))
        return p
    }
}

struct Whiskers: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in [-1.0, 0.0, 1.0] {
            let step = CGFloat(i)
            p.move(to: CGPoint(x: r.minX, y: r.midY + step * r.height * 0.45))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.3, y: r.midY + step * r.height * 0.12))
            p.move(to: CGPoint(x: r.maxX, y: r.midY + step * r.height * 0.45))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.3, y: r.midY + step * r.height * 0.12))
        }
        return p
    }
}

// MARK: - The pet (any animal), drawn like a soft plush toy

/// A little "w" mouth
struct WMouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let dip = r.minY + r.height * 2
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.25, y: dip))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.75, y: dip))
        return p
    }
}

struct PetFigure: View {
    var look: PetLook
    var stage: LifeStage = .adult
    var mood: PetMood = .happy
    var condition = PetCondition()
    var hatID: String? = nil
    var neckID: String? = nil
    var size: CGFloat = 160
    var animated = true
    /// Munching on a treat: head bobs and mouth opens and closes
    var chomping = false

    private var pal: PetPalette { look.palette }
    private var species: Species { look.species }
    private var s: CGFloat { size * stage.scale }
    private var eyeColor: Color { Color(red: 0.13, green: 0.1, blue: 0.1) }
    private static let cocoa = RGB(0.3, 0.2, 0.14)
    private var smallSnout: Bool { species == .cat || species == .bunny }

    /// Ears flop down when the pet is sleepy, sick or sad
    private var droopy: Bool {
        condition.sleeping || condition.sick || mood == .starving || mood == .grumpy
    }

    private var happyFace: Bool {
        (mood == .happy || mood == .thriving) && !condition.sleeping && !condition.sick
    }

    /// Seconds per tail wag. Happier pet = faster wag.
    private var wagPeriod: Double {
        if condition.sleeping || condition.sick { return 0 }
        switch mood {
        case .starving: return 0
        case .grumpy: return 1.6
        case .content: return 0.9
        case .happy: return 0.5
        case .thriving: return 0.32
        }
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                pose(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            pose(t: 0.5)
        }
    }

    private func pose(t: Double) -> some View {
        let wag: Double = wagPeriod > 0 ? 18 * sin(t * 2 * .pi / wagPeriod) : 0
        let breathe: CGFloat = condition.sleeping ? 1 + 0.03 * CGFloat(sin(t * 2 * .pi / 3)) : 1
        let bobAmount: CGFloat = condition.sleeping ? 0 : CGFloat(sin(t * 2 * .pi / (mood == .starving ? 3.0 : 1.5)))
        let bob: CGFloat = bobAmount * s * 0.015
        let blink: Bool = !condition.sleeping && t.truncatingRemainder(dividingBy: 4.1) < 0.13
        let headLift: CGFloat = (stage.headRatio - 1) * s * 0.33
        let munch: Double = chomping ? sin(t * 2 * .pi * 2.6) : 0
        let chompDip: CGFloat = chomping ? CGFloat(abs(munch)) * s * 0.05 + s * 0.03 : 0

        return ZStack {
            if stage == .radiant { radiantGlow(t: t) }
            Ellipse().fill(Color(red: 0.35, green: 0.23, blue: 0.15).opacity(0.18))
                .frame(width: s * 0.66, height: s * 0.09)
                .blur(radius: s * 0.015)
                .offset(y: s * 0.57)
            tailLayer(wag: wag)
            bodyLayer
            if let neckID {
                NeckArt(id: neckID, s: s)
                    .frame(width: s * 0.7, height: s * 0.3, alignment: .top)
                    .offset(y: s * 0.36)
            }
            headLayer(eyesClosed: blink || condition.sleeping, mouthOpen: munch > 0)
                .scaleEffect(stage.headRatio)
                .offset(y: -s * 0.12 - headLift * 0.5 + chompDip)
            if let hatID {
                HatArt(id: hatID, s: s)
                    .frame(width: s * 0.7, height: s * 0.4, alignment: .bottom)
                    .offset(y: -s * 0.6 - headLift)
            }
            if condition.dirty { flies(t: t) }
            if condition.sleeping { sleepZs(t: t) }
        }
        .scaleEffect(x: 1, y: breathe, anchor: .bottom)
        .frame(width: size * 1.1, height: size * 1.3)
        .padding(size * 0.5)
        .drawingGroup()
        .padding(-size * 0.5)
        .offset(y: bob)
    }

    /// Velvety plush shading: lighter where the light hits, a little deeper at the edges
    private func plush(_ base: RGB) -> RadialGradient {
        RadialGradient(colors: [base.mixed(with: RGB(1, 1, 1), 0.16).color,
                                base.color,
                                base.mixed(with: Self.cocoa, 0.14).color],
                       center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: s * 0.45)
    }

    /// A soft, squishy shape
    private func blob(_ w: CGFloat, _ h: CGFloat, _ base: RGB) -> some View {
        Ellipse()
            .fill(plush(base))
            .frame(width: w, height: h)
    }

    // MARK: Tail

    @ViewBuilder
    private func tailLayer(wag: Double) -> some View {
        switch species {
        case .dog:
            blob(s * 0.11, s * 0.3, pal.main)
                .rotationEffect(.degrees(35 + wag), anchor: .bottom)
                .offset(x: s * 0.3, y: s * 0.2)
        case .cat:
            blob(s * 0.08, s * 0.42, pal.main)
                .rotationEffect(.degrees(20 + wag * 0.5), anchor: .bottom)
                .offset(x: s * 0.33, y: s * 0.12)
        case .bunny:
            blob(s * 0.16, s * 0.15, pal.belly)
                .offset(x: s * 0.3, y: s * 0.42)
        case .panda:
            Circle().fill(pal.accent.color)
                .frame(width: s * 0.11, height: s * 0.11)
                .offset(x: s * 0.28, y: s * 0.44)
        case .fox:
            ZStack(alignment: .top) {
                blob(s * 0.24, s * 0.46, pal.main)
                Ellipse().fill(pal.belly.color)
                    .frame(width: s * 0.13, height: s * 0.15)
                    .offset(y: s * 0.01)
            }
            .rotationEffect(.degrees(35 + wag * 0.5), anchor: .bottom)
            .offset(x: s * 0.34, y: s * 0.12)
        }
    }

    // MARK: Body (sitting, round and chubby)

    private var footColor: RGB {
        (species == .panda || species == .fox) ? pal.accent : pal.main
    }

    private var bodyLayer: some View {
        ZStack {
            blob(s * 0.22, s * 0.13, footColor).offset(x: -s * 0.22, y: s * 0.53)
            blob(s * 0.22, s * 0.13, footColor).offset(x: s * 0.22, y: s * 0.53)
            blob(s * 0.6, s * 0.5, pal.main)
                .offset(y: s * 0.3)
            blob(s * 0.32, s * 0.3, pal.belly)
                .offset(y: s * 0.34)
            if species == .panda {
                Ellipse().fill(pal.accent.color)
                    .frame(width: s * 0.58, height: s * 0.14)
                    .offset(y: s * 0.13)
            }
            blob(s * 0.13, s * 0.27, footColor).rotationEffect(.degrees(6)).offset(x: -s * 0.11, y: s * 0.45)
            blob(s * 0.13, s * 0.27, footColor).rotationEffect(.degrees(-6)).offset(x: s * 0.11, y: s * 0.45)
            if condition.dirty { smudges }
        }
    }

    private var smudges: some View {
        let mud = Color(red: 0.45, green: 0.3, blue: 0.18).opacity(0.3)
        return ZStack {
            Circle().fill(mud).frame(width: s * 0.09, height: s * 0.09).offset(x: -s * 0.17, y: s * 0.28)
            Circle().fill(mud).frame(width: s * 0.06, height: s * 0.06).offset(x: s * 0.18, y: s * 0.4)
        }
    }

    // MARK: Head

    private func headLayer(eyesClosed: Bool, mouthOpen: Bool) -> some View {
        ZStack {
            backEars
            blob(s * 0.74, s * 0.62, pal.main)
            faceMarkings
            blob(s * (smallSnout ? 0.22 : 0.3), s * (smallSnout ? 0.15 : 0.2), pal.belly)
                .offset(y: s * 0.12)
            if species == .dog { dogEars }
            eye(closed: eyesClosed).offset(x: -s * 0.17, y: s * 0.02)
            eye(closed: eyesClosed).offset(x: s * 0.17, y: s * 0.02)
            cheeks
            nose
            mouth(open: mouthOpen)
            if condition.sick { sickLayer }
        }
    }

    @ViewBuilder
    private var backEars: some View {
        switch species {
        case .cat:
            pointyEar(height: 0.38, inner: pal.accent.color, side: -1).offset(x: -s * 0.22, y: -s * 0.33)
            pointyEar(height: 0.38, inner: pal.accent.color, side: 1).offset(x: s * 0.22, y: -s * 0.33)
        case .fox:
            pointyEar(height: 0.44, inner: pal.accent.color, side: -1).offset(x: -s * 0.22, y: -s * 0.36)
            pointyEar(height: 0.44, inner: pal.accent.color, side: 1).offset(x: s * 0.22, y: -s * 0.36)
        case .bunny:
            bunnyEar(side: -1).offset(x: -s * 0.13, y: -s * 0.42)
            bunnyEar(side: 1).offset(x: s * 0.13, y: -s * 0.42)
        case .panda:
            Circle().fill(pal.accent.color).frame(width: s * 0.2, height: s * 0.2).offset(x: -s * 0.27, y: -s * 0.24)
            Circle().fill(pal.accent.color).frame(width: s * 0.2, height: s * 0.2).offset(x: s * 0.27, y: -s * 0.24)
        case .dog:
            EmptyView()
        }
    }

    private func pointyEar(height: CGFloat, inner: Color, side: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Triangle().fill(pal.main.mixed(with: Self.cocoa, 0.08).color).frame(width: s * 0.26, height: s * height)
            Triangle().fill(inner).frame(width: s * 0.12, height: s * height * 0.6).offset(y: -s * 0.02)
        }
        .rotationEffect(.degrees(Double(side) * (droopy ? 35 : 12)), anchor: .bottom)
    }

    private func bunnyEar(side: CGFloat) -> some View {
        ZStack {
            blob(s * 0.17, s * 0.5, pal.main)
            Capsule().fill(pal.accent.color)
                .frame(width: s * 0.08, height: s * 0.34)
                .offset(y: s * 0.03)
        }
        .rotationEffect(.degrees(Double(side) * (droopy ? 55 : 8)), anchor: .bottom)
    }

    private var dogEars: some View {
        ZStack {
            blob(s * 0.2, s * 0.38, pal.accent)
                .rotationEffect(.degrees(droopy ? 4 : 12), anchor: .top)
                .offset(x: -s * 0.35, y: -s * 0.02)
            blob(s * 0.2, s * 0.38, pal.accent)
                .rotationEffect(.degrees(droopy ? -4 : -12), anchor: .top)
                .offset(x: s * 0.35, y: -s * 0.02)
        }
    }

    @ViewBuilder
    private var faceMarkings: some View {
        if species == .fox {
            Ellipse().fill(pal.belly.color).frame(width: s * 0.34, height: s * 0.26).offset(x: -s * 0.15, y: s * 0.13)
            Ellipse().fill(pal.belly.color).frame(width: s * 0.34, height: s * 0.26).offset(x: s * 0.15, y: s * 0.13)
        }
        if species == .panda {
            Ellipse().fill(pal.accent.color).frame(width: s * 0.18, height: s * 0.22)
                .rotationEffect(.degrees(30)).offset(x: -s * 0.15)
            Ellipse().fill(pal.accent.color).frame(width: s * 0.18, height: s * 0.22)
                .rotationEffect(.degrees(-30)).offset(x: s * 0.15)
        }
        if pal.blaze {
            RoundedRectangle(cornerRadius: s * 0.04)
                .fill(pal.belly.color)
                .frame(width: s * 0.08, height: s * 0.33)
                .offset(y: -s * 0.105)
        }
    }

    /// Little bead eyes, like a plush toy. Closed eyes are gentle curves; a thrilled pet squints happily.
    @ViewBuilder
    private func eye(closed: Bool) -> some View {
        let darkPatch = species == .panda && pal.accent.luminance < 0.4
        let ink = darkPatch ? Color.white.opacity(0.9) : eyeColor
        if closed {
            Mouth(curve: 0.5)
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.016, lineCap: .round))
                .frame(width: s * 0.075, height: s * 0.03)
        } else if mood == .thriving && happyFace {
            Mouth(curve: -0.7)
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.018, lineCap: .round))
                .frame(width: s * 0.075, height: s * 0.035)
        } else {
            ZStack {
                Ellipse().fill(eyeColor).frame(width: s * 0.065, height: s * 0.075)
                Circle().fill(Color.white.opacity(0.9))
                    .frame(width: s * 0.02, height: s * 0.02)
                    .offset(x: s * 0.012, y: -s * 0.016)
            }
        }
    }

    private var cheeks: some View {
        let blush = Color(red: 1, green: 0.55, blue: 0.6).opacity(0.35)
        return ZStack {
            Ellipse().fill(blush).frame(width: s * 0.12, height: s * 0.07).offset(x: -s * 0.24, y: s * 0.1)
            Ellipse().fill(blush).frame(width: s * 0.12, height: s * 0.07).offset(x: s * 0.24, y: s * 0.1)
        }
        .blur(radius: s * 0.01)
    }

    @ViewBuilder
    private var nose: some View {
        if smallSnout {
            Ellipse().fill(Color(red: 0.92, green: 0.55, blue: 0.59))
                .frame(width: s * 0.06, height: s * 0.042)
                .offset(y: s * 0.08)
        } else {
            ZStack {
                Ellipse().fill(Color(red: 0.27, green: 0.19, blue: 0.17))
                    .frame(width: s * 0.09, height: s * 0.062)
                Ellipse().fill(Color.white.opacity(0.35))
                    .frame(width: s * 0.03, height: s * 0.016)
                    .offset(x: -s * 0.015, y: -s * 0.012)
            }
            .offset(y: s * 0.075)
        }
    }

    @ViewBuilder
    private func mouth(open: Bool) -> some View {
        let mouthColor = Color(red: 0.31, green: 0.22, blue: 0.2)
        if chomping {
            Ellipse()
                .fill(Color(red: 0.55, green: 0.25, blue: 0.27))
                .frame(width: s * 0.09, height: open ? s * 0.08 : s * 0.025)
                .offset(y: s * 0.15)
        } else if happyFace || mood == .content || condition.sleeping {
            WMouth()
                .stroke(mouthColor, style: StrokeStyle(lineWidth: s * 0.011, lineCap: .round))
                .frame(width: s * 0.12, height: s * 0.025)
                .offset(y: s * 0.135)
            if mood == .thriving && happyFace && species == .dog {
                Ellipse().fill(Color(red: 1, green: 0.5, blue: 0.58))
                    .frame(width: s * 0.045, height: s * 0.05)
                    .offset(y: s * 0.17)
            }
        } else {
            Mouth(curve: mood == .starving ? -0.6 : -0.35)
                .stroke(mouthColor, style: StrokeStyle(lineWidth: s * 0.011, lineCap: .round))
                .frame(width: s * 0.1, height: s * 0.04)
                .offset(y: s * 0.15)
        }
    }

    // MARK: Conditions

    private var sickLayer: some View {
        ZStack {
            Ellipse().fill(Color.green.opacity(0.15))
                .frame(width: s * 0.74, height: s * 0.62)
            Image(systemName: "drop.fill")
                .font(.system(size: s * 0.09))
                .foregroundStyle(Color.cyan)
                .offset(x: s * 0.33, y: -s * 0.16)
        }
    }

    private func sleepZs(t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 0.5 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: s * (0.1 + 0.04 * CGFloat(i)), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .opacity(1 - phase)
                    .offset(x: s * (0.32 + 0.08 * CGFloat(i)), y: -s * (0.35 + 0.4 * CGFloat(phase)))
            }
        }
    }

    private func flies(t: Double) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let angle = t * 3 + Double(i) * 3
                Circle().fill(Color.black.opacity(0.7))
                    .frame(width: s * 0.03, height: s * 0.03)
                    .offset(x: CGFloat(cos(angle)) * s * 0.45, y: s * 0.2 + CGFloat(sin(angle * 1.7)) * s * 0.12)
            }
        }
    }

    private func radiantGlow(t: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.yellow.opacity(0.45), Color.clear],
                                     center: .center, startRadius: 0, endRadius: s * 0.7))
                .frame(width: s * 1.4, height: s * 1.4)
            ForEach(0..<4, id: \.self) { i in
                let angle = t * 0.8 + Double(i) * 1.57
                Image(systemName: "sparkle")
                    .font(.system(size: s * 0.1))
                    .foregroundStyle(Color.yellow)
                    .offset(x: CGFloat(cos(angle)) * s * 0.6, y: CGFloat(sin(angle)) * s * 0.5 - s * 0.05)
            }
        }
    }
}

// MARK: - Poop (junk photos live here)

struct PoopView: View {
    var size: CGFloat

    private let brown = Color(red: 0.55, green: 0.36, blue: 0.22)
    private let shine = Color(red: 0.72, green: 0.52, blue: 0.36)

    var body: some View {
        ZStack {
            VStack(spacing: -size * 0.1) {
                Triangle().fill(brown).frame(width: size * 0.16, height: size * 0.14)
                Ellipse().fill(brown).frame(width: size * 0.4, height: size * 0.24)
                Ellipse().fill(brown).frame(width: size * 0.66, height: size * 0.3)
                Ellipse().fill(brown).frame(width: size * 0.92, height: size * 0.34)
            }
            HStack(spacing: size * 0.14) {
                poopEye
                poopEye
            }
            .offset(y: size * 0.1)
            Ellipse().fill(shine.opacity(0.7))
                .frame(width: size * 0.14, height: size * 0.06)
                .offset(x: -size * 0.12, y: -size * 0.06)
        }
    }

    private var poopEye: some View {
        Circle().fill(.white)
            .frame(width: size * 0.11, height: size * 0.11)
            .overlay(Circle().fill(.black).frame(width: size * 0.055, height: size * 0.055))
    }
}

// MARK: - Hats

struct HatArt: View {
    let id: String
    let s: CGFloat

    var body: some View {
        switch id {
        case "party":
            ZStack(alignment: .top) {
                Triangle()
                    .fill(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.3, height: s * 0.36)
                Circle().fill(.yellow)
                    .frame(width: s * 0.09)
                    .offset(y: -s * 0.04)
            }
            .rotationEffect(.degrees(12))
            .offset(x: s * 0.06)
        case "beanie":
            VStack(spacing: -s * 0.03) {
                Circle().fill(.white).frame(width: s * 0.1)
                UnevenRoundedRectangle(topLeadingRadius: s * 0.22, topTrailingRadius: s * 0.22)
                    .fill(Color.blue)
                    .frame(width: s * 0.5, height: s * 0.2)
                RoundedRectangle(cornerRadius: s * 0.03)
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: s * 0.56, height: s * 0.08)
            }
            .offset(y: s * 0.07)
        case "bow":
            HStack(spacing: -s * 0.02) {
                Triangle().rotation(.degrees(90)).fill(Color.red).frame(width: s * 0.15, height: s * 0.15)
                Circle().fill(Color(red: 0.8, green: 0.1, blue: 0.2)).frame(width: s * 0.07)
                Triangle().rotation(.degrees(-90)).fill(Color.red).frame(width: s * 0.15, height: s * 0.15)
            }
            .rotationEffect(.degrees(-15))
            .offset(x: s * 0.2, y: s * 0.1)
        case "crown":
            Image(systemName: "crown.fill")
                .font(.system(size: s * 0.3))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .offset(y: s * 0.04)
        default:
            EmptyView()
        }
    }
}

// MARK: - Neckwear

struct NeckArt: View {
    let id: String
    let s: CGFloat

    var body: some View {
        switch id {
        case "bandana":
            ZStack(alignment: .top) {
                Triangle().rotation(.degrees(180))
                    .fill(Color.red)
                    .frame(width: s * 0.44, height: s * 0.24)
                HStack(spacing: s * 0.07) {
                    Circle().fill(.white.opacity(0.85)).frame(width: s * 0.03)
                    Circle().fill(.white.opacity(0.85)).frame(width: s * 0.03)
                }
                .offset(y: s * 0.04)
            }
        case "bowtie":
            HStack(spacing: -s * 0.02) {
                Triangle().rotation(.degrees(90)).fill(Color.indigo).frame(width: s * 0.14, height: s * 0.14)
                Circle().fill(Color.indigo.opacity(0.8)).frame(width: s * 0.07)
                Triangle().rotation(.degrees(-90)).fill(Color.indigo).frame(width: s * 0.14, height: s * 0.14)
            }
            .offset(y: s * 0.02)
        case "collar":
            ZStack(alignment: .top) {
                Capsule().fill(Color.red).frame(width: s * 0.48, height: s * 0.06)
                Circle().fill(Color(white: 0.88))
                    .overlay(Circle().stroke(Color(white: 0.6), lineWidth: s * 0.01))
                    .frame(width: s * 0.09)
                    .offset(y: s * 0.05)
            }
        case "scarf":
            ZStack(alignment: .topTrailing) {
                Capsule().fill(Color.mint).frame(width: s * 0.54, height: s * 0.1)
                RoundedRectangle(cornerRadius: s * 0.02)
                    .fill(Color.mint.opacity(0.85))
                    .frame(width: s * 0.1, height: s * 0.22)
                    .offset(x: -s * 0.08, y: s * 0.06)
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Soft shading shared by yard items and food

enum Soft {
    /// Plush-style shading: lighter where the light hits, a touch deeper at the edges
    static func fill(_ base: RGB, _ size: CGFloat) -> RadialGradient {
        RadialGradient(colors: [base.mixed(with: RGB(1, 1, 1), 0.22).color,
                                base.color,
                                base.mixed(with: RGB(0.3, 0.2, 0.14), 0.16).color],
                       center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: size * 0.6)
    }

    static let cream = RGB(0.99, 0.95, 0.88)
    static let terracotta = RGB(0.85, 0.51, 0.42)
    static let sage = RGB(0.6, 0.74, 0.56)
    static let sageDeep = RGB(0.45, 0.62, 0.45)
    static let mustard = RGB(0.93, 0.74, 0.3)
    static let wood = RGB(0.78, 0.58, 0.4)
    static let woodDark = RGB(0.56, 0.38, 0.25)
    static let pink = RGB(0.98, 0.72, 0.76)
    static let water = RGB(0.56, 0.78, 0.86)
    static let stone = RGB(0.78, 0.75, 0.7)
}

/// A wavy bottom edge, like an umbrella canopy or a shingled roof
struct Scallop: Shape {
    var bumps = 5

    func path(in r: CGRect) -> Path {
        var p = Path()
        let edge = r.maxY - r.height * 0.18
        p.move(to: CGPoint(x: r.minX, y: edge))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: edge), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.95))
        let step = r.width / CGFloat(bumps)
        for i in stride(from: bumps, to: 0, by: -1) {
            let x1 = r.minX + step * CGFloat(i)
            let x0 = x1 - step
            p.addQuadCurve(to: CGPoint(x: x0, y: edge), control: CGPoint(x: (x0 + x1) / 2, y: r.maxY + r.height * 0.1))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Yard items (soft, plush, cozy)

struct DecorArt: View {
    let id: String
    let size: CGFloat

    /// How big each item is relative to the others
    static func yardScale(_ id: String) -> CGFloat {
        switch id {
        case "doghouse": return 1.3
        case "tree": return 1.55
        case "pond": return 1.35
        case "umbrella": return 1.25
        case "lamp": return 1.0
        case "flowers": return 0.75
        case "bowl": return 0.6
        case "bed": return 1.05
        default: return 1.0
        }
    }

    var body: some View {
        Group {
            switch id {
            case "bowl": bowl
            case "flowers": flowers
            case "lamp": lantern
            case "tree": tree
            case "umbrella": umbrella
            case "bed": bed
            case "pond": pond
            case "doghouse": petHouse
            default:
                Circle().fill(Soft.fill(Soft.sage, size)).frame(width: size * 0.6, height: size * 0.6)
            }
        }
        .frame(width: size, height: size)
    }

    private func blob(_ w: CGFloat, _ h: CGFloat, _ c: RGB) -> some View {
        Ellipse().fill(Soft.fill(c, max(w, h))).frame(width: w, height: h)
    }

    private var groundShadow: some View {
        Ellipse().fill(Color(red: 0.3, green: 0.25, blue: 0.15).opacity(0.18))
            .blur(radius: size * 0.02)
    }

    // A ceramic bowl with a little mound of kibble
    private var bowl: some View {
        ZStack {
            groundShadow.frame(width: size * 0.8, height: size * 0.14).offset(y: size * 0.24)
            ForEach(0..<6, id: \.self) { i in
                Circle().fill(Soft.fill(Soft.woodDark, size * 0.12))
                    .frame(width: size * 0.13, height: size * 0.13)
                    .offset(x: size * CGFloat([-0.16, -0.05, 0.06, 0.17, -0.1, 0.1][i]),
                            y: size * CGFloat([-0.02, -0.06, -0.05, -0.01, 0.0, 0.0][i]))
            }
            UnevenRoundedRectangle(topLeadingRadius: size * 0.04, bottomLeadingRadius: size * 0.3,
                                   bottomTrailingRadius: size * 0.3, topTrailingRadius: size * 0.04)
                .fill(Soft.fill(Soft.terracotta, size))
                .frame(width: size * 0.74, height: size * 0.28)
                .offset(y: size * 0.12)
            Capsule().fill(Soft.cream.color).frame(width: size * 0.74, height: size * 0.06).offset(y: size * 0.02)
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.1))
                .foregroundStyle(Soft.cream.color.opacity(0.9))
                .offset(y: size * 0.14)
        }
    }

    // Three soft flowers on leaves
    private var flowers: some View {
        ZStack {
            groundShadow.frame(width: size * 0.8, height: size * 0.14).offset(y: size * 0.3)
            blob(size * 0.34, size * 0.16, Soft.sage).rotationEffect(.degrees(-25)).offset(x: -size * 0.2, y: size * 0.2)
            blob(size * 0.34, size * 0.16, Soft.sageDeep).rotationEffect(.degrees(25)).offset(x: size * 0.2, y: size * 0.2)
            blob(size * 0.3, size * 0.14, Soft.sage).offset(y: size * 0.26)
            flower(Soft.pink, size * 0.34).offset(x: -size * 0.18, y: -size * 0.02)
            flower(Soft.mustard, size * 0.3).offset(x: size * 0.2, y: size * 0.02)
            flower(RGB(0.97, 0.82, 0.72), size * 0.36).offset(y: -size * 0.2)
        }
    }

    private func flower(_ petal: RGB, _ d: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let angle = Double(i) / 5 * 2 * .pi
                Circle().fill(Soft.fill(petal, d * 0.5))
                    .frame(width: d * 0.48, height: d * 0.48)
                    .offset(x: CGFloat(cos(angle)) * d * 0.26, y: CGFloat(sin(angle)) * d * 0.26)
            }
            Circle().fill(Soft.fill(RGB(0.96, 0.82, 0.45), d * 0.3)).frame(width: d * 0.32, height: d * 0.32)
        }
    }

    // A wooden post with a warm glowing lantern
    private var lantern: some View {
        ZStack {
            groundShadow.frame(width: size * 0.4, height: size * 0.1).offset(y: size * 0.46)
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.5).opacity(0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.32))
                .frame(width: size * 0.64, height: size * 0.64)
                .offset(y: -size * 0.22)
            Capsule().fill(Soft.fill(Soft.wood, size)).frame(width: size * 0.08, height: size * 0.62).offset(y: size * 0.16)
            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(Soft.fill(Soft.woodDark, size * 0.3))
                .frame(width: size * 0.3, height: size * 0.06)
                .offset(y: -size * 0.08)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.7), Color(red: 1, green: 0.78, blue: 0.4)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .stroke(Soft.woodDark.color, lineWidth: size * 0.025))
                .frame(width: size * 0.24, height: size * 0.26)
                .offset(y: -size * 0.24)
            Triangle().fill(Soft.fill(Soft.woodDark, size * 0.3))
                .frame(width: size * 0.32, height: size * 0.12)
                .offset(y: -size * 0.42)
        }
    }

    // A fluffy round tree with little blossoms
    private var tree: some View {
        ZStack {
            groundShadow.frame(width: size * 0.7, height: size * 0.12).offset(y: size * 0.44)
            UnevenRoundedRectangle(topLeadingRadius: size * 0.03, bottomLeadingRadius: size * 0.08,
                                   bottomTrailingRadius: size * 0.08, topTrailingRadius: size * 0.03)
                .fill(Soft.fill(Soft.wood, size * 0.5))
                .frame(width: size * 0.14, height: size * 0.4)
                .offset(y: size * 0.26)
            blob(size * 0.5, size * 0.44, Soft.sageDeep).offset(x: -size * 0.18, y: -size * 0.02)
            blob(size * 0.5, size * 0.44, Soft.sageDeep).offset(x: size * 0.18, y: -size * 0.02)
            blob(size * 0.56, size * 0.5, Soft.sage).offset(y: -size * 0.2)
            blob(size * 0.36, size * 0.3, RGB(0.68, 0.8, 0.6)).offset(x: -size * 0.08, y: -size * 0.28)
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(Soft.fill(Soft.pink, size * 0.06))
                    .frame(width: size * 0.07, height: size * 0.07)
                    .offset(x: size * CGFloat([-0.24, 0.05, 0.22, -0.06, 0.28][i]),
                            y: size * CGFloat([-0.06, -0.36, -0.14, 0.06, 0.04][i]))
            }
        }
    }

    // A striped, scalloped garden umbrella
    private var umbrella: some View {
        ZStack {
            groundShadow.frame(width: size * 0.8, height: size * 0.14).offset(y: size * 0.44)
            Capsule().fill(Soft.fill(Soft.wood, size)).frame(width: size * 0.05, height: size * 0.7).offset(y: size * 0.1)
            ZStack {
                Scallop(bumps: 6).fill(Soft.fill(Soft.cream, size))
                Scallop(bumps: 6)
                    .fill(Soft.fill(Soft.terracotta, size))
                    .mask(
                        HStack(spacing: size * 0.13) {
                            ForEach(0..<4, id: \.self) { _ in Rectangle().frame(width: size * 0.13) }
                        }
                    )
            }
            .frame(width: size * 0.92, height: size * 0.36)
            .offset(y: -size * 0.24)
            Circle().fill(Soft.fill(Soft.woodDark, size * 0.06)).frame(width: size * 0.06, height: size * 0.06).offset(y: -size * 0.47)
        }
    }

    // A squishy round pet bed with a cushion
    private var bed: some View {
        ZStack {
            groundShadow.frame(width: size * 0.95, height: size * 0.2).offset(y: size * 0.18)
            blob(size * 0.92, size * 0.44, Soft.sage).offset(y: size * 0.06)
            blob(size * 0.66, size * 0.26, Soft.cream).offset(y: size * 0.04)
            Capsule().fill(Soft.fill(Soft.pink, size * 0.2))
                .frame(width: size * 0.22, height: size * 0.08)
                .rotationEffect(.degrees(-12))
                .offset(x: -size * 0.14, y: -size * 0.02)
        }
    }

    // A little pond with stones and lily pads
    private var pond: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                let angle = Double(i) / 9 * 2 * .pi
                blob(size * 0.2, size * 0.14, Soft.stone)
                    .offset(x: CGFloat(cos(angle)) * size * 0.42, y: CGFloat(sin(angle)) * size * 0.17 + size * 0.1)
            }
            Ellipse()
                .fill(RadialGradient(colors: [RGB(0.72, 0.88, 0.93).color, Soft.water.color, RGB(0.42, 0.65, 0.76).color],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.45))
                .frame(width: size * 0.84, height: size * 0.36)
                .offset(y: size * 0.1)
            Capsule().fill(Color.white.opacity(0.6)).frame(width: size * 0.16, height: size * 0.025).offset(x: size * 0.16, y: size * 0.04)
            blob(size * 0.16, size * 0.08, Soft.sageDeep).offset(x: -size * 0.18, y: size * 0.12)
            blob(size * 0.12, size * 0.06, Soft.sage).offset(x: size * 0.1, y: size * 0.17)
            flower(Soft.pink, size * 0.12).offset(x: -size * 0.18, y: size * 0.09)
        }
    }

    // A cozy pet house with a scalloped roof and round door
    private var petHouse: some View {
        ZStack {
            groundShadow.frame(width: size * 0.9, height: size * 0.14).offset(y: size * 0.42)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Soft.fill(Soft.wood, size))
                .frame(width: size * 0.74, height: size * 0.5)
                .offset(y: size * 0.16)
            UnevenRoundedRectangle(topLeadingRadius: size * 0.14, topTrailingRadius: size * 0.14)
                .fill(Soft.woodDark.mixed(with: RGB(0.2, 0.12, 0.08), 0.4).color)
                .frame(width: size * 0.28, height: size * 0.3)
                .offset(y: size * 0.26)
            Scallop(bumps: 5)
                .fill(Soft.fill(Soft.terracotta, size))
                .frame(width: size * 0.95, height: size * 0.42)
                .offset(y: -size * 0.16)
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.09))
                .foregroundStyle(Soft.cream.color)
                .offset(y: size * 0.02)
        }
    }
}

// MARK: - Food and toys (so you can watch your pal eat and play)

struct FoodArt: View {
    let id: String
    let size: CGFloat

    var body: some View {
        Group {
            switch id {
            case "kibble": kibble
            case "berries": berries
            case "carrot": carrot
            case "bamboo": bamboo
            case "salmon": salmon
            case "pupcake": pupcake
            case "tennis": tennis
            case "squeaky": bird
            case "winetoy": wineToy
            case "music": musicBox
            case "medicine": medicine
            default: Circle().fill(Soft.fill(Soft.mustard, size)).frame(width: size * 0.5, height: size * 0.5)
            }
        }
        .frame(width: size, height: size)
    }

    private func blob(_ w: CGFloat, _ h: CGFloat, _ c: RGB) -> some View {
        Ellipse().fill(Soft.fill(c, max(w, h))).frame(width: w, height: h)
    }

    private var kibble: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: size * 0.06)
                    .fill(Soft.fill(i % 2 == 0 ? Soft.woodDark : Soft.wood, size * 0.2))
                    .frame(width: size * 0.2, height: size * 0.16)
                    .rotationEffect(.degrees(Double(i) * 37))
                    .offset(x: size * CGFloat([-0.2, 0, 0.2, -0.1, 0.1, -0.02, 0.24][i]),
                            y: size * CGFloat([0.1, 0.12, 0.1, -0.02, -0.02, -0.14, -0.06][i]))
            }
        }
    }

    private var berries: some View {
        ZStack {
            blob(size * 0.3, size * 0.14, Soft.sageDeep).rotationEffect(.degrees(-30)).offset(x: -size * 0.04, y: -size * 0.24)
            blob(size * 0.36, size * 0.36, RGB(0.85, 0.3, 0.4)).offset(x: -size * 0.14, y: size * 0.04)
            blob(size * 0.34, size * 0.34, RGB(0.45, 0.45, 0.75)).offset(x: size * 0.16, y: size * 0.08)
            blob(size * 0.3, size * 0.3, RGB(0.9, 0.38, 0.45)).offset(x: size * 0.02, y: -size * 0.1)
        }
    }

    private var carrot: some View {
        ZStack {
            blob(size * 0.12, size * 0.3, Soft.sageDeep).rotationEffect(.degrees(-25)).offset(x: size * 0.22, y: -size * 0.3)
            blob(size * 0.12, size * 0.3, Soft.sage).rotationEffect(.degrees(15)).offset(x: size * 0.3, y: -size * 0.28)
            Triangle()
                .fill(Soft.fill(RGB(0.96, 0.58, 0.25), size))
                .frame(width: size * 0.3, height: size * 0.8)
                .rotationEffect(.degrees(205))
                .offset(x: -size * 0.04, y: size * 0.04)
        }
    }

    private var bamboo: some View {
        ZStack {
            Capsule().fill(Soft.fill(RGB(0.62, 0.78, 0.45), size)).frame(width: size * 0.18, height: size * 0.85)
                .rotationEffect(.degrees(20))
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(RGB(0.48, 0.64, 0.36).color).frame(width: size * 0.2, height: size * 0.03)
                    .offset(y: size * (CGFloat(i) - 1) * 0.24)
                    .rotationEffect(.degrees(20))
            }
            blob(size * 0.3, size * 0.13, Soft.sageDeep).rotationEffect(.degrees(-20)).offset(x: size * 0.18, y: -size * 0.22)
        }
    }

    private var salmon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(Soft.fill(RGB(0.98, 0.6, 0.5), size))
                .frame(width: size * 0.76, height: size * 0.42)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.65)).frame(width: size * 0.04, height: size * 0.32)
                    .rotationEffect(.degrees(20))
                    .offset(x: size * (CGFloat(i) - 1) * 0.18)
            }
        }
    }

    private var pupcake: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: size * 0.02, bottomLeadingRadius: size * 0.08,
                                   bottomTrailingRadius: size * 0.08, topTrailingRadius: size * 0.02)
                .fill(Soft.fill(Soft.terracotta, size))
                .frame(width: size * 0.5, height: size * 0.3)
                .offset(y: size * 0.2)
            blob(size * 0.62, size * 0.3, Soft.pink).offset(y: size * 0.02)
            blob(size * 0.46, size * 0.24, RGB(0.99, 0.82, 0.85)).offset(y: -size * 0.1)
            blob(size * 0.26, size * 0.16, Soft.pink).offset(y: -size * 0.22)
            Circle().fill(Soft.fill(RGB(0.85, 0.25, 0.3), size * 0.14)).frame(width: size * 0.14, height: size * 0.14).offset(y: -size * 0.33)
        }
    }

    private var tennis: some View {
        ZStack {
            Circle().fill(Soft.fill(RGB(0.85, 0.92, 0.4), size)).frame(width: size * 0.66, height: size * 0.66)
            Circle().trim(from: 0.1, to: 0.4).stroke(Color.white.opacity(0.9), lineWidth: size * 0.04)
                .frame(width: size * 0.5, height: size * 0.5).offset(x: -size * 0.2)
            Circle().trim(from: 0.6, to: 0.9).stroke(Color.white.opacity(0.9), lineWidth: size * 0.04)
                .frame(width: size * 0.5, height: size * 0.5).offset(x: size * 0.2)
        }
    }

    private var bird: some View {
        ZStack {
            blob(size * 0.64, size * 0.56, Soft.mustard)
            blob(size * 0.26, size * 0.18, RGB(0.95, 0.82, 0.5)).rotationEffect(.degrees(-20)).offset(x: -size * 0.12, y: size * 0.06)
            Triangle().fill(Soft.terracotta.color).frame(width: size * 0.14, height: size * 0.1)
                .rotationEffect(.degrees(90)).offset(x: size * 0.36, y: -size * 0.04)
            Circle().fill(Color(red: 0.2, green: 0.15, blue: 0.14)).frame(width: size * 0.06, height: size * 0.06).offset(x: size * 0.16, y: -size * 0.1)
        }
    }

    private var wineToy: some View {
        ZStack {
            Capsule().fill(Soft.fill(RGB(0.42, 0.14, 0.2), size)).frame(width: size * 0.34, height: size * 0.62).offset(y: size * 0.1)
            Capsule().fill(Soft.fill(RGB(0.42, 0.14, 0.2), size)).frame(width: size * 0.14, height: size * 0.3).offset(y: -size * 0.28)
            Capsule().fill(Soft.fill(RGB(0.75, 0.25, 0.3), size)).frame(width: size * 0.16, height: size * 0.08).offset(y: -size * 0.42)
            RoundedRectangle(cornerRadius: size * 0.03).fill(Soft.cream.color).frame(width: size * 0.28, height: size * 0.18).offset(y: size * 0.12)
        }
    }

    private var musicBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Soft.fill(Soft.wood, size)).frame(width: size * 0.7, height: size * 0.46).offset(y: size * 0.1)
            RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                .fill(Soft.fill(Soft.woodDark, size)).frame(width: size * 0.76, height: size * 0.12).offset(y: -size * 0.14)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.26, weight: .bold))
                .foregroundStyle(Soft.mustard.color)
                .offset(x: size * 0.2, y: -size * 0.34)
        }
    }

    private var medicine: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(Soft.fill(RGB(0.95, 0.95, 0.96), size)).frame(width: size * 0.46, height: size * 0.6).offset(y: size * 0.08)
            RoundedRectangle(cornerRadius: size * 0.05).fill(Soft.fill(Soft.terracotta, size)).frame(width: size * 0.34, height: size * 0.14).offset(y: -size * 0.26)
            Image(systemName: "cross.fill")
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(Color.red.opacity(0.75))
                .offset(y: size * 0.1)
        }
    }
}

// MARK: - Small icon for any shop item

struct ItemIcon: View {
    let item: ShopItem

    var body: some View {
        switch item.category {
        case .hat:
            HatArt(id: item.id, s: 95).frame(width: 50, height: 50)
        case .neck:
            NeckArt(id: item.id, s: 95).frame(width: 50, height: 50)
        case .decor:
            DecorArt(id: item.id, size: 34).frame(width: 50, height: 50)
        case .food, .toy, .care:
            FoodArt(id: item.id, size: 42).frame(width: 50, height: 50)
        }
    }
}
