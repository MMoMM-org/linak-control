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
    /// Examples:
    ///   display(mm: 1105, unit: .cm)   → "110.5 cm"
    ///   display(mm: 1105, unit: .inch) → "43.5 in"
    public static func display(mm: Int, unit: HeightUnit) -> String {
        switch unit {
        case .cm:
            return String(format: "%.1f cm", toCentimeters(mm))
        case .inch:
            return String(format: "%.1f in", toInches(mm))
        }
    }
}
