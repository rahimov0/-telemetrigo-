import Foundation
@testable import KrovaCore

/// Tekrarlanabilir rastgele sayı üreteci (SplitMix64)
struct RNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func gauss(_ sd: Double) -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

struct Scenario {
    var seconds = 600
    var speed = 1.4            // gerçek hız m/s (0 = duruyor)
    var hAcc = 8.0
    var corrSD = 3.0           // ilişkili (yavaş değişen) konum gürültüsü, m
    var tau = 12.0
    var whiteSD = 1.0
    var wiggle = 0.0           // yolun virajlılığı
    var jumps: [Int] = []      // tek ölçümlük sıçramalar
    var tunnel: Range<Int>? = nil
    var invalidSpeedRate = 0.1
}

/// Gerçek yolu ve ölçümleri üretir; gerçek mesafeyi de döndürür.
func generate(_ sc: Scenario, seed: UInt64) -> (fixes: [Fix], truth: Double) {
    var rng = RNG(seed)
    let a = exp(-1 / sc.tau), sig = sc.corrSD * (1 - a * a).squareRoot()
    var x = 0.0, y = 0.0, heading = 0.5, truth = 0.0, ex = 0.0, ey = 0.0
    var out: [Fix] = []
    let k = 111_320.0, lat0 = 41.0, lon0 = 29.0
    for t in 0..<sc.seconds {
        var v = 0.0
        if sc.speed > 0 {
            v = max(0, sc.speed * (1 + 0.08 * sin(Double(t) / 17)) + rng.gauss(0.05 * sc.speed))
            heading += sc.wiggle * sin(Double(t) / 23) * 0.2 + rng.gauss(0.02)
        }
        x += v * cos(heading); y += v * sin(heading); truth += v
        ex = a * ex + rng.gauss(sig); ey = a * ey + rng.gauss(sig)
        var mx = x + ex + rng.gauss(sc.whiteSD), my = y + ey + rng.gauss(sc.whiteSD)
        var h = sc.hAcc
        if let tn = sc.tunnel, tn.contains(t) { h = 45; mx += rng.gauss(25); my += rng.gauss(25) }
        var sp = rng.uniform() < sc.invalidSpeedRate ? -1.0 : max(0, v + rng.gauss(sc.speed > 0 ? 0.12 : 0.15))
        if sc.speed == 0 && sp >= 0 { sp = abs(rng.gauss(0.12)) }
        if sc.jumps.contains(t) { mx += (rng.uniform() < 0.5 ? -60 : 60); my += (rng.uniform() < 0.5 ? -40 : 40) }
        let cosLat = cos(lat0 * .pi / 180)
        out.append(Fix(t: Double(t), lat: lat0 + my / k, lon: lon0 + mx / (k * cosLat), hAcc: h, speed: sp))
    }
    return (out, truth)
}

func runScenario(_ kind: ActivityKind, _ sc: Scenario, seed: UInt64) -> (engine: DistanceEngine, truth: Double) {
    let g = generate(sc, seed: seed)
    var e = DistanceEngine(kind: kind)
    for f in g.fixes { e.add(f) }
    return (e, g.truth)
}

/// Birkaç tohum üzerinde en kötü yüzde sapma
func worstErrorPercent(_ kind: ActivityKind, _ sc: Scenario, seeds: Int = 12) -> Double {
    var worst = 0.0
    for s in 0..<seeds {
        let r = runScenario(kind, sc, seed: UInt64(s) &* 131 &+ 7)
        worst = max(worst, abs(r.engine.distance / r.truth - 1) * 100)
    }
    return worst
}
