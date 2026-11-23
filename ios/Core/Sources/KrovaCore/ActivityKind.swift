import Foundation

/// Aktivite grubu: spor (fiziksel) ve sürüş ayrı mantıkta çalışır.
public enum ActivityGroup: String, Codable, Sendable { case sport, drive }

/// Tüm tür kuralları tek yerde. Ekranlar `kind == .motor` gibi karşılaştırma yapmaz, buradan okur.
public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case walk, run, hike, bike, motorcycle, car

    public var group: ActivityGroup {
        switch self {
        case .walk, .run, .hike, .bike: return .sport
        case .motorcycle, .car: return .drive
        }
    }
    /// Kalori hesaplanır mı
    public var countsCalories: Bool { group == .sport }
    /// Günlük halkalara / hedeflere sayılır mı
    public var countsTowardGoals: Bool { group == .sport }
    /// Apple Sağlık'a antrenman olarak yazılır mı
    public var writesToHealth: Bool { group == .sport }
    /// Otomatik duraklatma desteklenir mi
    public var supportsAutoPause: Bool { group == .sport }
    /// Otomatik duraklatma varsayılanı (yürüyüş ve tırmanmada kapalı: yavaş hareketi durma sanmasın)
    public var autoPauseDefault: Bool { self == .run || self == .bike }
    /// Ana gösterge tempo (dk/km) mi, hız (km/s) mi
    public var showsPace: Bool { self == .walk || self == .run || self == .hike }

    /// Bu hızın altı (m/s) "duruyor" sayılır
    public var stopSpeed: Double {
        switch self {
        case .walk: return 0.35
        case .run: return 0.8
        case .hike: return 0.3
        case .bike: return 1.0
        case .motorcycle, .car: return 1.5
        }
    }
    /// Makul üst hız (m/s): üstü GPS hatası/sıçrama sayılır
    public var maxPlausibleSpeed: Double {
        switch self {
        case .walk: return 3.0
        case .run: return 7.0
        case .hike: return 2.5
        case .bike: return 20.0
        case .motorcycle, .car: return 75.0
        }
    }
    /// Bu doğruluktan (m) kötü konumlar atılır
    public var maxAccuracy: Double { 30.0 }
}
