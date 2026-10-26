import Foundation

/// Presentation only. Never feed these strings back into verification,
/// calculations, persistence, confidence checks or comparison decisions.
enum ChartNumberFormat {
    static let note = "Displays use at most two decimal places. Calculations and editable values keep full precision. Confirmation does not make an estimate an exact measurement."

    static func rounded(_ value: Decimal) -> Decimal {
        var input = value, result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    static func isRounded(_ value: Decimal) -> Bool { !value.isNaN && rounded(value) != value }

    static func number(_ value: Decimal, locale: Locale = .current) -> String {
        guard !value.isNaN else { return "Unavailable" }
        let displayed = rounded(value)
        var input = displayed, integral = Decimal()
        NSDecimalRound(&integral, &input, 0, .down)
        let minimum = integral == displayed ? 0 : 2
        return displayed.formatted(.number.precision(.fractionLength(minimum...2)).locale(locale))
    }

    static func number(_ value: Double, locale: Locale = .current) -> String {
        guard let value = decimal(value) else { return "Unavailable" }
        return number(value, locale: locale)
    }

    static func percent(_ percentage: Decimal, locale: Locale = .current) -> String {
        guard !percentage.isNaN else { return "Unavailable" }
        // Chart percentages are already on a 0–100 scale, not 0–1 fractions.
        let value = rounded(percentage)
        var input = value, integral = Decimal()
        NSDecimalRound(&integral, &input, 0, .down)
        return value.formatted(.percent.scale(1).precision(.fractionLength(integral == value ? 0...2 : 2...2)).locale(locale))
    }

    static func readable(_ value: Decimal, approximate: Bool = false, locale: Locale = .current) -> String {
        guard !value.isNaN else { return "Unavailable" }
        if value != 0, rounded(value) == 0 {
            let edge = Decimal(string: "0.01")!
            return value > 0
                ? "between " + number(Decimal.zero, locale: locale) + " and " + number(edge, locale: locale)
                : "between " + number(-edge, locale: locale) + " and " + number(Decimal.zero, locale: locale)
        }
        return (approximate || isRounded(value) ? "approximately " : "") + number(value, locale: locale)
    }

    static func readable(_ value: Double, locale: Locale = .current) -> String {
        guard let value = decimal(value) else { return "Unavailable" }
        return readable(value, locale: locale)
    }

    /// Speech may use a whole number only when its display error is at most 1%
    /// and the magnitude is at least ten. Shares retain two-decimal precision.
    /// This never participates in a calculation or a verification decision.
    static func spoken(_ value: Decimal, estimated: Bool = false, preferWhole: Bool = true, locale: Locale = .current) -> String {
        guard !value.isNaN else { return "unavailable" }
        if preferWhole, abs(value) >= 10 {
            var input = value, whole = Decimal()
            NSDecimalRound(&whole, &input, 0, .plain)
            if case .success(let error) = CheckedDecimal.calculate(value, whole, .subtract),
               case .success(let budget) = CheckedDecimal.calculate(abs(value), Decimal(string: "0.01")!, .multiply),
               abs(error.value) <= budget.value {
                return (estimated || whole != value ? "about " : "") + number(whole, locale: locale)
            }
        }
        return readable(value, approximate: estimated, locale: locale).replacingOccurrences(of: "approximately ", with: "about ")
    }

    private static func decimal(_ value: Double) -> Decimal? {
        guard value.isFinite else { return nil }
        return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
    }
}
