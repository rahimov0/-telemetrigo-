import Foundation

/// Tek bir GPS ölçümü (CoreLocation'dan bağımsız, test edilebilir)
public struct Fix: Sendable, Equatable {
    public var t: Double          // saniye (epoch)
    public var lat: Double
    public var lon: Double
    public var hAcc: Double       // yatay doğruluk, m (negatif = geçersiz)
    public var speed: Double      // m/s; negatif = geçersiz (Doppler yok)
    public init(t: Double, lat: Double, lon: Double, hAcc: Double, speed: Double) {
        self.t = t; self.lat = lat; self.lon = lon; self.hAcc = hAcc; self.speed = speed
    }
}

public func meters(_ a: Fix, _ b: Fix) -> Double {
    let k = 111_320.0
    let dy = (a.lat - b.lat) * k
    let dx = (a.lon - b.lon) * k * cos((a.lat + b.lat) / 2 * .pi / 180)
    return (dx * dx + dy * dy).squareRoot()
}

/// Mesafe ve hareket süresi: ana yöntem Doppler hızının integrali; hız yoksa son 8 sn'lik yer değiştirme.
/// Sıçrama (makul hızın üstü) ve duruş gürültüsü (durma hızının altı) sayılmaz.
public struct DistanceEngine: Sendable {
    public let kind: ActivityKind
    public private(set) var distance: Double = 0
    public private(set) var movingTime: Double = 0
    public private(set) var maxSpeed: Double = 0
    public private(set) var dopplerFixes = 0
    public private(set) var chordFixes = 0
    public private(set) var rejectedFixes = 0

    private var prev: Fix?
    private var hist: [Fix] = []
    private var lastDoppler: (t: Double, v: Double)?
    private let window = 8.0

    /// Hız verisinin geçerli olduğu ölçüm oranı (düşükse arayüz "GPS hız verisi yok, mesafe tahmini" uyarısı gösterir)
    public var dopplerRatio: Double { let n = dopplerFixes + chordFixes; return n == 0 ? 1 : Double(dopplerFixes) / Double(n) }

    public init(kind: ActivityKind) { self.kind = kind }

    /// Duraklatma/devam gibi kopukluklarda çağır: sonraki ölçüm yeni parçanın başı olur (aradaki yol sayılmaz).
    public mutating func breakSegment() { prev = nil; hist = []; lastDoppler = nil }

    /// Ölçümü işler; bu aralıkta kullanılan hızı (m/s) döndürür.
    @discardableResult
    public mutating func add(_ f: Fix) -> Double {
        guard f.hAcc >= 0, f.hAcc <= kind.maxAccuracy else { rejectedFixes += 1; return 0 }
        hist.append(f)
        hist.removeAll { f.t - $0.t > window + 6 }
        guard let p = prev else { prev = f; return 0 }
        let dt = f.t - p.t
        guard dt > 0 else { return 0 }

        if dt > 10 {                                   // boşluk (tünel, sinyal kaybı)
            let chord = meters(p, f)
            if dt <= 120, chord > 15, chord / dt <= kind.maxPlausibleSpeed {
                distance += chord
                if chord / dt >= kind.stopSpeed { movingTime += dt }
            }
            prev = f; hist = [f]
            return 0
        }

        var v: Double
        if f.speed >= 0 {
            v = f.speed; dopplerFixes += 1
            lastDoppler = (f.t, f.speed)
        } else if let d = lastDoppler, f.t - d.t <= 3 {   // kısa Doppler kesintisi: son değeri tut
            v = d.v
        } else {                                       // uzun kesinti: yer değiştirmeden hız
            chordFixes += 1
            v = 0
            if let old = hist.first(where: { f.t - $0.t >= window * 0.8 }) {
                let span = f.t - old.t
                let ch = meters(old, f)
                if span > 0, ch >= max(4.0, 0.5 * f.hAcc) { v = ch / span }
            }
        }
        if v > kind.maxPlausibleSpeed * 1.3 { v = 0; rejectedFixes += 1 }   // sıçrama
        if v < kind.stopSpeed { v = 0 }
        if v > 0 {
            distance += v * dt
            movingTime += dt
            if v <= kind.maxPlausibleSpeed { maxSpeed = max(maxSpeed, v) }
        }
        prev = f
        return v
    }
}
