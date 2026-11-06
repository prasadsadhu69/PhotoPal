import Foundation
import UserNotifications

/// Local reminders (no server needed). Rescheduled every time the app closes,
/// so they always match your pal's latest state.
enum PeanutNotifier {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(for game: GameState) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let name = game.petName
        let cal = Calendar.current
        let now = Date()

        // 1. Hungry: when the hunger meter will hit about 25%
        let hoursUntilHungry = (game.food - 25) / (game.sleeping ? 1.5 : 3)
        if hoursUntilHungry > 0.25 {
            add(center, id: "hungry",
                title: "\(name) is getting hungry",
                body: "Their tummy is rumbling. Scoop some poop and grab a treat!",
                at: awakeTime(now.addingTimeInterval(hoursUntilHungry * 3600)))
        }

        // 2. Sleepy: when energy runs low (only while awake)
        if !game.sleeping {
            let hoursUntilSleepy = (game.energy - 15) / 4
            if hoursUntilSleepy > 0.25 {
                add(center, id: "sleepy",
                    title: "\(name) is yawning",
                    body: "Time to turn off the lights so they can rest.",
                    at: awakeTime(now.addingTimeInterval(hoursUntilSleepy * 3600)))
            }
        }

        // 3. Sick: remind to give medicine
        if game.sick {
            add(center, id: "sick",
                title: "\(name) doesn't feel well",
                body: "Give them medicine, and scoop some poop so the yard stays clean.",
                at: awakeTime(now.addingTimeInterval(2 * 3600)))
        }

        // 4. Evening poop patrol, every day at 7pm
        var patrol = DateComponents()
        patrol.hour = 19
        patrol.minute = 0
        center.add(UNNotificationRequest(
            identifier: "patrol",
            content: content(title: "Poop patrol!", body: "\(name) is sniffing for new poop in your camera roll. Come scoop it!"),
            trigger: UNCalendarNotificationTrigger(dateMatching: patrol, repeats: true)))

        // 5. Memory dig, every morning at 10
        var dig = DateComponents()
        dig.hour = 10
        dig.minute = 0
        center.add(UNNotificationRequest(
            identifier: "dig",
            content: content(title: "\(name) dug up a memory", body: "Come see which photo from this day \(name) found."),
            trigger: UNCalendarNotificationTrigger(dateMatching: dig, repeats: true)))

        // 6. Streak: 8pm on the day it would break
        if game.streak > 0, let last = game.lastPlayDay {
            var target: Date?
            let evening = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
            if cal.isDateInToday(last) {
                target = cal.date(byAdding: .day, value: 1, to: evening)
            } else if cal.isDateInYesterday(last) {
                target = evening > now ? evening : nil
            }
            if let target {
                add(center, id: "streak",
                    title: "Keep your \(game.streak)-day streak!",
                    body: "Scoop at least one poop today so \(name) stays proud.",
                    at: target)
            }
        }
    }

    private static func content(title: String, body: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        return c
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, title: String, body: String, at date: Date) {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content(title: title, body: body), trigger: trigger))
    }

    /// Moves a time between 10pm and 9am to 9am, so nobody gets pinged at 3am
    private static func awakeTime(_ date: Date) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        if hour >= 22 {
            let nextDay = cal.date(byAdding: .day, value: 1, to: date) ?? date
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay) ?? date
        }
        if hour < 9 {
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        return date
    }
}
