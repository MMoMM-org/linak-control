// HeightConverter.swift
// LinakControl

public enum HeightConverter {
    /// Convert mm to centimeters as Double (e.g. 1105 → 110.5)
    public static func toCentimeters(_ mm: Int) -> Double {
        Double(mm) / 10.0
    }

    /// Convert mm to inches as Double (e.g. 1105 → 43.5)
    public static func toInches(_ mm: Int) -> Double {
        Double(mm) / 25.4
    }

    /// Convert height in mm to a localized display string.
    ///
    /// Fractional digits are shown only when non-zero:
    ///   display(mm: 1105, unit: .cm)   -> "110.5 cm"
    ///   display(mm: 700,  unit: .cm)   -> "70 cm"
    ///   display(mm: 1105, unit: .inch) -> "43.5 in"
    public static func display(mm: Int, unit: HeightUnit) -> String {
        switch unit {
        case .cm:
            return formatDecimal(toCentimeters(mm), suffix: "cm")
        case .inch:
            return formatDecimal(toInches(mm), suffix: "in")
        }
    }

    /// Formats a decimal value with 1 fractional digit if non-zero, 0 otherwise.
    private static func formatDecimal(_ value: Double, suffix: String) -> String {
        let fractional = value.truncatingRemainder(dividingBy: 1)
        if abs(fractional) < 0.05 {
            return "\(Int(value.rounded())) \(suffix)"
        }
        return String(format: "%.1f \(suffix)", value)
    }
}
