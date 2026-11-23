import SwiftUI
import KrovaCore
import CoreLocation

// MARK: Renk sistemi: her değerin kendi rengi var (süre sarı, mesafe mavi, tempo camgöbeği, kalori pembe, yükseliş yeşil, adım mor)
extension Theme {
    static let cDist = Color(red: 0.30, green: 0.64, blue: 1.0)     // #4DA3FF
    static let cTime = Color(red: 1.0, green: 0.84, blue: 0.04)     // #FFD60A
    static let cPace = Color(red: 0.39, green: 0.82, blue: 1.0)     // #64D2FF
    static let cKcal = Color(red: 1.0, green: 0.22, blue: 0.37)     // #FF375F
    static let cElev = Color(red: 0.19, green: 0.82, blue: 0.35)    // #30D158
    static let cSteps = Color(red: 0.75, green: 0.35, blue: 0.95)   // #BF5AF2
    static let cMax = Color(red: 1.0, green: 0.62, blue: 0.04)      // #FF9F0A
}

extension ActType {
    /// Türün rengi: harita rotası, simge, başlat düğmesi
    var color: Color {
        switch self {
        case .yuruyus: return Color(red: 0.20, green: 0.85, blue: 0.55)   // nane yeşili
        case .kosu: return Color(red: 1.0, green: 0.55, blue: 0.10)       // turuncu
        case .bisiklet: return Color(red: 0.30, green: 0.64, blue: 1.0)   // mavi
        case .motor: return Color(red: 1.0, green: 0.28, blue: 0.36)      // kırmızı
        }
    }
}

/// Hıza göre rota rengi: yavaş camgöbeği → sarı → hızlı pembe
func speedColor(_ t: Double) -> Color {
    let a = (0.39, 0.82, 1.0), b = (1.0, 0.84, 0.04), c = (1.0, 0.22, 0.37)
    let x = min(max(t, 0), 1)
    let (p, q, u) = x < 0.5 ? (a, b, x * 2) : (b, c, (x - 0.5) * 2)
    return Color(red: p.0 + (q.0 - p.0) * u, green: p.1 + (q.1 - p.1) * u, blue: p.2 + (q.2 - p.2) * u)
}

struct RouteSeg: Identifiable { let id: Int; let coords: [CLLocationCoordinate2D]; let color: Color }

/// Rotayı parçalara bölüp her parçayı o bölgedeki hıza göre renklendirir
func routeSegments(_ pts: [TrackPoint]) -> [RouteSeg] {
    guard pts.count > 4 else { return [] }
    let chunk = max(4, pts.count / 90)
    var raw: [(coords: [CLLocationCoordinate2D], v: Double)] = []
    var i = 0
    while i < pts.count - 1 {
        let j = min(i + chunk, pts.count - 1)
        let slice = Array(pts[i...j])
        let dt = max(slice.last!.t - slice.first!.t, 0.5)
        var d = 0.0
        for k in 1..<slice.count {
            d += CLLocation(latitude: slice[k - 1].la, longitude: slice[k - 1].lo).distance(from: CLLocation(latitude: slice[k].la, longitude: slice[k].lo))
        }
        raw.append((slice.map { CLLocationCoordinate2D(latitude: $0.la, longitude: $0.lo) }, d / dt))
        i = j
    }
    let sorted = raw.map { $0.v }.sorted()
    let lo = sorted[Int(Double(sorted.count - 1) * 0.1)], hi = sorted[Int(Double(sorted.count - 1) * 0.9)]
    return raw.enumerated().map { RouteSeg(id: $0.offset, coords: $0.element.coords, color: speedColor(hi > lo ? ($0.element.v - lo) / (hi - lo) : 0.5)) }
}

// MARK: Kalori (MET tabanlı, aktif = dinlenme enerjisi çıkarılmış)
enum Cal {
    static var kg: Double { UserDefaults.standard.double(forKey: "profKg") }
    static var cm: Double { UserDefaults.standard.double(forKey: "profCm") }
    static var ready: Bool { kg >= 25 }

    /// Aktif kalori (kcal); sürüş türlerinde, kilo girilmemişse ya da süre kısaysa nil
    static func active(_ t: ActType, dist: Double, moving: Double) -> Double? {
        Calories.active(kind: t.kind, distance: dist, movingTime: moving, weightKg: kg)
    }
    static func active(_ a: Activity) -> Double? { active(a.type, dist: a.distance, moving: a.moving) }
}

// MARK: Hedef halkası
struct GoalRing: View {
    let value: Double, goal: Double
    let color: Color, icon: String
    var size: CGFloat = 78
    var body: some View {
        let f = goal > 0 ? min(value / goal, 1) : 0
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: 10)
            Circle().trim(from: 0, to: max(f, 0.004)).stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: icon).font(.system(size: size * 0.27, weight: .bold)).foregroundStyle(color)
        }.frame(width: size, height: size)
    }
}

/// Üstte hafif renkli ışık veren arka plan
struct Glow: View {
    var color: Color = Theme.acc
    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg
            RadialGradient(colors: [color.opacity(0.30), color.opacity(0)], center: .top, startRadius: 0, endRadius: 380).frame(height: 420)
        }.ignoresSafeArea()
    }
}
