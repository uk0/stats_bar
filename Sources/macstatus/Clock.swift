import Foundation

/// Beijing time (Asia/Shanghai), regardless of the machine's own time zone.
/// `now()` is the full "yyyy-MM-dd HH:mm" (dropdown / tooltip); `compact()`
/// drops the year to "MM-dd HH:mm" for the narrow status-bar strip.
enum Clock {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = format
        return f
    }

    private static let full = make("yyyy-MM-dd HH:mm")
    private static let short = make("MM-dd HH:mm")

    static func now() -> String { full.string(from: Date()) }
    static func compact() -> String { short.string(from: Date()) }
}
