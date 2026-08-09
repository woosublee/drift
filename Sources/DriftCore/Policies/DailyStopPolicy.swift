import Foundation

public struct DailyStopTrigger: Codable, Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public struct DailyStopPolicy {
    public init() {}

    public func trigger(
        now: Date,
        settings: DailyStopSettings,
        lastTrigger: DailyStopTrigger?,
        calendar: Calendar
    ) -> DailyStopTrigger? {
        guard settings.isEnabled else { return nil }
        let values = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: now)
        guard let year = values.year,
              let month = values.month,
              let day = values.day,
              let weekday = values.weekday,
              values.hour == settings.hour,
              values.minute == settings.minute,
              settings.weekdays.contains(weekday) else {
            return nil
        }
        let trigger = DailyStopTrigger(year: year, month: month, day: day)
        return trigger == lastTrigger ? nil : trigger
    }
}
