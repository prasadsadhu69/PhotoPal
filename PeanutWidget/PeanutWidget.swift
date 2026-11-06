import WidgetKit
import SwiftUI

// Shows your pal on the Home Screen with today's mood and poop count.
// Uses Models.swift and DogArt.swift from the app (shared with this widget target).

struct PeanutEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PeanutProvider: TimelineProvider {
    func placeholder(in context: Context) -> PeanutEntry {
        PeanutEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PeanutEntry) -> Void) {
        completion(PeanutEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .sample))
    }

    /// One entry per hour for the next 12 hours, so your pal gets hungrier on the widget too
    func getTimeline(in context: Context, completion: @escaping (Timeline<PeanutEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .sample
        let now = Date()
        let entries = (0..<12).map { hour in
            PeanutEntry(date: now.addingTimeInterval(Double(hour) * 3600), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PeanutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PeanutEntry

    private var stats: (food: Double, joy: Double) { entry.snapshot.projected(at: entry.date) }
    private var mood: PetMood { PetMood.from(food: stats.food, joy: stats.joy, clean: entry.snapshot.clean) }
    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 12) {
                    pal(size: 92)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snap.name).font(.headline)
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        bar("fork.knife", stats.food, .orange)
                        bar("heart.fill", stats.joy, .pink)
                        bar("sparkles", snap.clean, .teal)
                    }
                }
            } else {
                VStack(spacing: 2) {
                    pal(size: 64)
                    Text(snap.sleeping ? "\(snap.name) is asleep" : "\(snap.name) is \(mood.rawValue.lowercased())")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if snap.poops > 0 {
                        HStack(spacing: 4) {
                            PoopView(size: 14).frame(width: 16, height: 14)
                            Text("\(snap.poops) to scoop")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("All clean!").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.91), Color(red: 1, green: 0.8, blue: 0.86)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func pal(size: CGFloat) -> some View {
        PetFigure(look: snap.look, stage: snap.stage, mood: mood,
                  condition: PetCondition(sleeping: snap.sleeping, sick: snap.sick, dirty: snap.clean < 50),
                  hatID: snap.hatID, neckID: snap.neckID, size: size, animated: false)
            .frame(width: size * 1.1, height: size * 1.3)
    }

    private func bar(_ symbol: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(color).frame(width: 14)
            ProgressView(value: min(max(value, 0), 100), total: 100).tint(color)
        }
    }

    private var line: String {
        if snap.sleeping { return "Sleeping. Shh..." }
        if snap.sick { return "\(snap.name) feels sick. Medicine helps!" }
        if snap.poops > 0 { return "\(snap.poops) poops to scoop!" }
        switch mood {
        case .starving: return "\(snap.name) is starving!"
        case .grumpy: return "\(snap.name) needs some love."
        case .content: return "\(snap.name) is doing okay."
        case .happy: return "\(snap.name) is wagging away."
        case .thriving: return "\(snap.name) is living the dream!"
        }
    }
}

struct PeanutWidget: Widget {
    let kind = "PeanutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PeanutProvider()) { entry in
            PeanutWidgetView(entry: entry)
        }
        .configurationDisplayName("PhotoPal")
        .description("See how your pal is doing and how much poop is waiting.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
