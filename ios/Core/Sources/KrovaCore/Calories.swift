import Foundation

public enum Calories {
    /// MET (metabolik eşdeğer) tahmini; hıza göre
    public static func met(_ kind: ActivityKind, kmh: Double) -> Double {
        switch kind {
        case .walk:
            switch kmh { case ..<3.2: return 2.5; case ..<4.0: return 2.9; case ..<4.8: return 3.3; case ..<5.6: return 3.8; case ..<6.4: return 5.0; default: return 7.0 }
        case .run: return max(6.0, kmh)
        case .hike: return 6.0
        case .bike:
            switch kmh { case ..<12: return 4.0; case ..<16: return 5.8; case ..<19: return 6.8; case ..<22: return 8.0; case ..<25.7: return 10.0; case ..<30: return 12.0; default: return 15.8 }
        case .motorcycle, .car: return 1.0
        }
    }

    /// Aktif kalori (dinlenme enerjisi çıkarılmış): (MET − 1) · kg · saat.
    /// Sürüş türlerinde ve kilo/süre yetersizse nil.
    public static func active(kind: ActivityKind, distance: Double, movingTime: Double, weightKg: Double) -> Double? {
        guard kind.countsCalories, weightKg >= 25, movingTime >= 30 else { return nil }
        let kmh = distance / movingTime * 3.6
        return max(0, (met(kind, kmh: kmh) - 1) * weightKg * movingTime / 3600)
    }
}

public enum Validity {
    /// Çok kısa kayıt: 20 m'den az ya da 15 sn'den az hareket
    public static func isTooShort(distance: Double, movingTime: Double) -> Bool {
        distance < 20 || movingTime < 15
    }
}
