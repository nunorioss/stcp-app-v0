//
//  DateUtil.swift
//  stcp-app
//
//  Created by Nuno Rios on 14/06/2026.
//

import Foundation

nonisolated enum DateUtil {
    static let secondsPerDay = 86_400
    
    /// Gregorian calendar fixed to mainland Portugal's timezone.
    public static let portoCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()
    
    /// Seconds since midnight in Porto for a given date.
    public static func secondsSinceMidnight(at date: Date = Date()) -> Int {
        let components = portoCalendar.dateComponents([.hour, .minute, .second], from: date)
        return components.hour! * 3600 + components.minute! * 60 + components.second!
    }
    
    /// True between 00:20 and 06:00 in Porto, during "dawn".
    public static func isDawnTime(at date: Date = Date()) -> Bool {
        let seconds = secondsSinceMidnight(at: date)
        return seconds >= 1200 && seconds < 21600
    }
    
    static func clock(_ hour: Int, _ minute: Int) -> String {
        "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
    }

    /// Returns the time in Porto's timezone (HH:mm).
    public static func clockText(for date: Date) -> String {
        let c = portoCalendar.dateComponents(
            [.hour, .minute],
            from: date
        )
        return clock(c.hour ?? 0, c.minute ?? 0)
    }
    
    public static func formatInterval(_ minutes: Int) -> String {
        if minutes < 1 {
            return "now"
        }
        if minutes < 60 {
            return "\(minutes)min"
        }

        let hours = minutes / 60
        if hours < 24 {
            let m = minutes % 60
            return m == 0 ? "\(hours)h" : "\(hours)h\(m)min"
        }

        let d = hours / 24
        let h = hours % 24
        return h == 0 ? "\(d)d" : "\(d)d\(h)h"
    }

    /// Formats an Arrival occurring tomorrow through seven days from now.
    public static func formatUpcomingDate(for date: Date, now: Date = .now) -> String {
        var calendar = portoCalendar
        calendar.locale = Locale(identifier: "en_US")

        let today = calendar.startOfDay(for: now)
        let targetDay = calendar.startOfDay(for: date)

        let days = calendar.dateComponents(
            [.day],
            from: today,
            to: targetDay
        ).day ?? 0

        let components = calendar.dateComponents(
            [.hour, .minute, .weekday],
            from: date
        )

        guard let hour = components.hour,
              let minute = components.minute,
              let weekday = components.weekday else {
            return "?"
        }

        let time = clock(hour, minute)
        if days == 1 {
            return "Tomorrow at \(time)"
        }

        assert((2...7).contains(days))
        return "\(calendar.weekdaySymbols[weekday - 1]) at \(time)"
    }
}
