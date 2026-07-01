import Foundation

/// Beijing time (Asia/Shanghai), formatted "yyyy-MM-dd HH:mm" regardless of the
/// machine's own time zone. Shared by the status bar and the --once diagnostic.
enum Clock {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func now() -> String { formatter.string(from: Date()) }
}
