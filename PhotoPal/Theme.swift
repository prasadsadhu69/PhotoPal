import SwiftUI
import UIKit

/// "Tactile papercraft and cozy home": oatmeal paper, terracotta, sage, mustard, wood and felt
enum Theme {
    // Palette
    static let oatmeal = Color(red: 0.992, green: 0.984, blue: 0.969)      // #FDFBF7 background
    static let paper = Color(red: 1.0, green: 0.992, blue: 0.976)
    static let cocoa = Color(red: 0.35, green: 0.25, blue: 0.2)            // text
    static let terracotta = Color(red: 0.85, green: 0.51, blue: 0.42)
    static let sage = Color(red: 0.6, green: 0.72, blue: 0.58)
    static let sageDeep = Color(red: 0.42, green: 0.57, blue: 0.43)
    static let mustard = Color(red: 0.89, green: 0.7, blue: 0.24)
    static let woodLight = Color(red: 0.8, green: 0.62, blue: 0.43)
    static let woodDark = Color(red: 0.6, green: 0.42, blue: 0.28)
    static let cork = Color(red: 0.86, green: 0.71, blue: 0.53)
    static let dustyBlue = Color(red: 0.55, green: 0.66, blue: 0.78)
    static let plum = Color(red: 0.62, green: 0.5, blue: 0.68)

    // Older names, kept so every screen picks up the new palette
    static let cream = oatmeal
    static let berry = terracotta
    static let peach = Color(red: 0.98, green: 0.82, blue: 0.7)
    static let leaf = sage
    static let honey = mustard
    static let mint = sageDeep
    static let lilac = plum
    static let sky = dustyBlue

    // Type: rounded, friendly headers (Fredoka) with clean system body text
    static func header(_ size: CGFloat, _ weight: String = "SemiBold", relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom("Fredoka-\(weight)", size: size, relativeTo: style)
    }
    static let largeTitle = header(32, "Bold", relativeTo: .largeTitle)
    static let title = header(26, "Bold", relativeTo: .title)
    static let title2 = header(22, "SemiBold", relativeTo: .title2)
    static let title3 = header(20, "SemiBold", relativeTo: .title3)
    static let headline = header(17, "SemiBold", relativeTo: .headline)
    static let label = header(13, "Medium", relativeTo: .caption)
}

// MARK: - Textures

/// Textures are drawn once into small images and then tiled, so scrolling stays smooth
enum Texture {
    private static func random(_ seed: inout UInt64) -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
    }

    /// Paper flecks on a transparent 160x160 tile
    static let paper: UIImage = {
        let size = CGSize(width: 160, height: 160)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            var seed: UInt64 = 42
            for _ in 0..<420 {
                let x = Texture.random(&seed) * size.width
                let y = Texture.random(&seed) * size.height
                let r = 0.5 + Texture.random(&seed) * 1.0
                let brown = Texture.random(&seed) > 0.5
                let alpha = 0.5 + Texture.random(&seed) * 0.5
                let color = brown ? UIColor(red: 0.55, green: 0.4, blue: 0.25, alpha: alpha) : UIColor(white: 0, alpha: alpha)
                color.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
    }()

    /// Wood grain lines on a transparent 240x60 tile
    static let wood: UIImage = {
        let size = CGSize(width: 240, height: 60)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            var seed: UInt64 = 7
            var y: CGFloat = 4
            let cg = ctx.cgContext
            while y < size.height {
                let wobble = 1.5 + Texture.random(&seed) * 2.5
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y))
                path.addCurve(to: CGPoint(x: size.width, y: y),
                              controlPoint1: CGPoint(x: size.width * 0.33, y: y - wobble),
                              controlPoint2: CGPoint(x: size.width * 0.66, y: y + wobble))
                UIColor(red: 0.6, green: 0.42, blue: 0.28, alpha: 0.2 + Texture.random(&seed) * 0.15).setStroke()
                path.lineWidth = 0.8 + Texture.random(&seed)
                cg.addPath(path.cgPath)
                cg.strokePath()
                y += 5 + Texture.random(&seed) * 6
            }
        }
    }()
}

/// Subtle paper grain
struct PaperGrain: View {
    var opacity: Double = 0.07

    var body: some View {
        Image(uiImage: Texture.paper)
            .resizable(resizingMode: .tile)
            .opacity(min(1, opacity * 1.6))
            .allowsHitTesting(false)
    }
}

/// Wood grain lines for panels and buttons
struct WoodGrain: View {
    var body: some View {
        Image(uiImage: Texture.wood)
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
    }
}

// MARK: - Surfaces

/// A sheet of soft paper
struct PaperCard: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.paper)
                    .shadow(color: Theme.cocoa.opacity(0.12), radius: 6, y: 3)
                    .overlay(PaperGrain().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.cocoa.opacity(0.07), lineWidth: 1))
            }
    }
}

/// A rounded wooden board
struct WoodPanel: ViewModifier {
    var radius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.woodLight, Theme.woodLight.opacity(0.92), Theme.woodDark.opacity(0.85)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(WoodGrain().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                        .padding(1.5))
                    .shadow(color: Theme.cocoa.opacity(0.25), radius: 10, y: 4)
            }
    }
}

/// A felt patch with a little stitched border
struct FeltBadge: ViewModifier {
    var color: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(color)
                    .overlay(PaperGrain(opacity: 0.12).clipShape(Capsule()))
                    .overlay(Capsule().inset(by: 2.5)
                        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, dash: [3, 2.5])))
            }
    }
}

extension View {
    func paperCard(padding: CGFloat = 14, radius: CGFloat = 22) -> some View {
        modifier(PaperCard(padding: padding, radius: radius))
    }

    func woodPanel(radius: CGFloat = 26) -> some View {
        modifier(WoodPanel(radius: radius))
    }

    func feltBadge(_ color: Color) -> some View {
        modifier(FeltBadge(color: color))
    }

    /// Older name for paper cards
    func cozyCard(padding: CGFloat = 14) -> some View {
        modifier(PaperCard(padding: padding))
    }

    /// Oatmeal paper background for a whole screen
    func paperBackground() -> some View {
        background {
            ZStack {
                Theme.oatmeal
                PaperGrain(opacity: 0.05)
            }
            .ignoresSafeArea()
        }
    }
}
