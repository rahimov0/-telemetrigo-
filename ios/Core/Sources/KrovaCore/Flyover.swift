import Foundation

/// Flyover için rotanın mesafeye göre eşit aralıklı örneklenmiş hâli: kamera sabit hızla ilerler, durağan anlar videoyu bekletmez.
public struct FlyoverTrack: Sendable {
    public struct Sample: Sendable { public var lat, lon, dist, time, ele, gain, heading: Double }
    public struct Input: Sendable {
        public var lat, lon, t: Double; public var ele: Double?
        public init(lat: Double, lon: Double, t: Double, ele: Double? = nil) { self.lat = lat; self.lon = lon; self.t = t; self.ele = ele }
    }
    public let samples: [Sample]
    public var totalDistance: Double { samples.last?.dist ?? 0 }
    public var totalTime: Double { samples.last?.time ?? 0 }

    public static func meters(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6_371_000.0, p1 = a.0 * .pi / 180, p2 = b.0 * .pi / 180
        let dp = p2 - p1, dl = (b.1 - a.1) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
    static func bearing(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let p1 = a.0 * .pi / 180, p2 = b.0 * .pi / 180, dl = (b.1 - a.1) * .pi / 180
        let y = sin(dl) * cos(p2), x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// lookMeters / smoothMeters: kameranın baktığı ileri mesafe ve yön yumuşatma penceresi (metre). Verilmezse rotanın uzunluğuna göre.
    public init?(points: [Input], count: Int? = nil, lookMeters: Double? = nil, smoothMeters: Double? = nil) {
        guard points.count >= 2 else { return nil }
        var cum = [0.0]
        for i in 1..<points.count { cum.append(cum[i - 1] + Self.meters((points[i - 1].lat, points[i - 1].lon), (points[i].lat, points[i].lon))) }
        guard let total = cum.last, total > 5 else { return nil }
        let n = max(count ?? min(1200, max(400, Int(total / 15))), 20), spacing = total / Double(n - 1)
        var raw: [Sample] = []
        var j = 0
        var acc = GainAccumulator(threshold: 1.5)
        var lastEle = points.first(where: { $0.ele != nil })?.ele ?? 0
        for k in 0..<n {
            let d = total * Double(k) / Double(n - 1)
            while j < points.count - 2 && cum[j + 1] < d { j += 1 }
            let seg = max(cum[j + 1] - cum[j], 0.0001), u = min(max((d - cum[j]) / seg, 0), 1)
            let a = points[j], b = points[j + 1]
            if let e = a.ele, let f = b.ele { lastEle = e + (f - e) * u } else if let e = a.ele ?? b.ele { lastEle = e }
            acc.add(lastEle)
            raw.append(Sample(lat: a.lat + (b.lat - a.lat) * u, lon: a.lon + (b.lon - a.lon) * u, dist: d,
                              time: (a.t + (b.t - a.t) * u) - points[0].t, ele: lastEle, gain: acc.gain, heading: 0))
        }
        // Yön: ileriye bakan ortalama; ani dönüşlerde kamera sallanmasın diye birim vektörlerle yumuşatılır
        let look = lookMeters.map { max(2, Int($0 / spacing)) } ?? max(4, n / 25)
        let win = smoothMeters.map { max(2, Int($0 / spacing)) } ?? max(3, n / 20)
        var dir: [Double] = []
        for k in 0..<n {
            let to = min(n - 1, k + look), from = k
            dir.append(to > from ? Self.bearing((raw[from].lat, raw[from].lon), (raw[to].lat, raw[to].lon)) : (dir.last ?? 0))
        }
        for k in 0..<n {
            var sx = 0.0, sy = 0.0
            for m in max(0, k - win)...min(n - 1, k + win) { sx += sin(dir[m] * .pi / 180); sy += cos(dir[m] * .pi / 180) }
            raw[k].heading = (atan2(sx, sy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        }
        samples = raw
    }

    /// 0...1 ilerlemeye göre örnek (iki komşu arasında doğrusal)
    public func state(at p: Double) -> Sample {
        let x = min(max(p, 0), 1) * Double(samples.count - 1)
        let i = min(Int(x), samples.count - 2), u = x - Double(i)
        let a = samples[i], b = samples[i + 1]
        var dh = b.heading - a.heading; if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        return Sample(lat: a.lat + (b.lat - a.lat) * u, lon: a.lon + (b.lon - a.lon) * u, dist: a.dist + (b.dist - a.dist) * u,
                      time: a.time + (b.time - a.time) * u, ele: a.ele + (b.ele - a.ele) * u, gain: a.gain + (b.gain - a.gain) * u,
                      heading: (a.heading + dh * u + 360).truncatingRemainder(dividingBy: 360))
    }
    /// O ana kadar çizilecek rota noktaları (son nokta ara değerli)
    public func path(upTo p: Double) -> [(lat: Double, lon: Double)] {
        let x = min(max(p, 0), 1) * Double(samples.count - 1)
        let i = Int(x)
        var out = samples[0...min(i, samples.count - 1)].map { (lat: $0.lat, lon: $0.lon) }
        let s = state(at: p); out.append((lat: s.lat, lon: s.lon))
        return out
    }
    /// Son `seconds` saniyedeki ortalama hız (m/s): ekrandaki canlı tempo/hız
    public func speed(at p: Double, window seconds: Double = 20) -> Double {
        let now = state(at: p)
        var lo = p, step = 1.0 / Double(samples.count * 2)
        while lo > 0, now.time - state(at: lo).time < seconds { lo = max(0, lo - step); step *= 1.0 }
        let then = state(at: lo)
        let dt = now.time - then.time
        return dt > 0.5 ? (now.dist - then.dist) / dt : 0
    }
}
