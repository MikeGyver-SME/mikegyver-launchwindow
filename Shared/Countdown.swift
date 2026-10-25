import Foundation

enum Countdown {
    /// "T-2d 4h", "T-3h 12m", "T-14m", or "T+5m" after liftoff time.
    static func tMinus(to net: Date, from now: Date = .now) -> String {
        let seconds = Int(net.timeIntervalSince(now))
        let sign = seconds >= 0 ? "T-" : "T+"
        let s = abs(seconds)
        let d = s / 86_400
        let h = (s % 86_400) / 3_600
        let m = (s % 3_600) / 60
        if d > 0 { return "\(sign)\(d)d \(h)h" }
        if h > 0 { return "\(sign)\(h)h \(m)m" }
        if m > 0 { return "\(sign)\(m)m" }
        // Was "T-0m" for a full minute before liftoff; show seconds instead.
        return "\(sign)\(s % 60)s"
    }
}
