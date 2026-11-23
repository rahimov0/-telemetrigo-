import Foundation
import CoreLocation
import AVFoundation
import KrovaCore

/// Aktivite türleri (web tarafıyla aynı anahtarlar)
enum ActType: String, Codable, CaseIterable, Identifiable {
    /// Aktivite sekmesinde kaydedilebilen türler (motor sürüşü Sürüş sekmesinde)
    static var sport: [ActType] { [.yuruyus, .kosu, .bisiklet] }
    case yuruyus, kosu, bisiklet, motor
    var id: String { rawValue }
    var name: String { ["yuruyus": "Yürüyüş", "kosu": "Koşu", "bisiklet": "Bisiklet", "motor": "Motor"][rawValue]! }
    var icon: String { ["yuruyus": "figure.walk", "kosu": "figure.run", "bisiklet": "bicycle", "motor": "motorcycle"][rawValue]! }
    /// Makul üst hız (m/s): GPS sıçramalarını "en iyi tempo"dan ayıklar
    var maxPlausible: Double { switch self { case .yuruyus: return 3.0; case .kosu: return 7.0; case .bisiklet: return 20; case .motor: return 75 } }
    var pace: Bool { self == .yuruyus || self == .kosu }
    /// Çekirdek paketteki tür kuralları (kalori, halka, Sağlık, otomatik duraklat burada karar verilir)
    var kind: ActivityKind { switch self { case .yuruyus: return .walk; case .kosu: return .run; case .bisiklet: return .bike; case .motor: return .motorcycle } }
    /// bunun altı "duruyor" (otomatik duraklatma), m/s
    var stopSpeed: Double { ["yuruyus": 0.3, "kosu": 0.7, "bisiklet": 1.0, "motor": 1.5][rawValue]! }
    /// bu pencerede (sn) bu kadar metreden az yer değiştirdiyse gerçekten duruyor demektir
    var stillWindow: Double { ["yuruyus": 14, "kosu": 10, "bisiklet": 8, "motor": 8][rawValue]! }
    var stillDist: Double { ["yuruyus": 5, "kosu": 5, "bisiklet": 7, "motor": 10][rawValue]! }
    var clType: CLActivityType {
        switch self {
        case .yuruyus, .kosu: return .fitness
        case .bisiklet: return .otherNavigation
        case .motor: return .automotiveNavigation
        }
    }
    func title(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        let part = h < 5 ? "Gece" : h < 11 ? "Sabah" : h < 14 ? "Öğle" : h < 18 ? "Öğleden sonra" : h < 22 ? "Akşam" : "Gece"
        let w = ["yuruyus": "yürüyüşü", "kosu": "koşusu", "bisiklet": "bisiklet turu", "motor": "sürüşü"][rawValue]!
        return "\(part) \(w)"
    }
}

struct Activity: Codable, Identifiable, Hashable {
    var id: String
    var type: ActType
    var start: Date
    var end: Date?
    var distance: Double = 0     // m
    var moving: Double = 0       // sn
    var gain: Double = 0         // m
    var maxSpeed: Double = 0     // m/s
    var preview: [[Double]]? = nil   // rota küçük resmi için seyreltilmiş [enlem, boylam]
    var gpxName: String { "Aktivite_\(Session.nameFmt.string(from: start)).gpx" }
}

struct TrackPoint: Codable {
    var t: Double; var la: Double; var lo: Double
    var al: Double?; var ha: Double; var sp: Double?
}

enum Fmt {
    static func dur(_ s: Double) -> String {
        let s = max(0, Int(s.rounded())), h = s / 3600, m = s / 60 % 60, x = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
    }
    static func pace(_ v: Double) -> String {
        guard v > 0.3 else { return "—" }
        let s = Int((1000 / v).rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func km(_ m: Double) -> String { String(format: "%.2f", m / 1000).replacingOccurrences(of: ".", with: ",") }
    static func num(_ v: Double, _ d: Int = 0) -> String { String(format: "%.\(d)f", v).replacingOccurrences(of: ".", with: ",") }
}

/// Aktivite kaydı: arka planda GPS, otomatik duraklatma, kilometre başına sesli bildirim
final class ActivityRecorder: NSObject, ObservableObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
    enum State { case idle, running, paused }
    @Published var state: State = .idle
    @Published var type: ActType = ActType(rawValue: UserDefaults.standard.string(forKey: "actType") ?? "") ?? .kosu {
        didSet {
            UserDefaults.standard.set(type.rawValue, forKey: "actType")
            if oldValue != type { autoPause = Self.autoPauseSetting(type) }
        }
    }
    /// Otomatik duraklatma türe göre saklanır; yürüyüşte varsayılan kapalı (yavaş yürüyüşü durmuş sanmasın)
    @Published var autoPause: Bool = ActivityRecorder.autoPauseSetting(ActType(rawValue: UserDefaults.standard.string(forKey: "actType") ?? "") ?? .kosu) {
        didSet { UserDefaults.standard.set(autoPause, forKey: "autoPause2_" + type.rawValue) }
    }
    static func autoPauseSetting(_ t: ActType) -> Bool {
        guard t.kind.supportsAutoPause else { return false }
        return UserDefaults.standard.object(forKey: "autoPause2_" + t.rawValue) as? Bool ?? t.kind.autoPauseDefault
    }
    @Published var voiceEvery: Int = max(1, UserDefaults.standard.integer(forKey: "voiceEvery")) { didSet { UserDefaults.standard.set(voiceEvery, forKey: "voiceEvery") } }
    @Published var voice = UserDefaults.standard.object(forKey: "voice") as? Bool ?? true { didSet { UserDefaults.standard.set(voice, forKey: "voice") } }
    @Published var autoPaused = false
    @Published var current: Activity?
    @Published var moving: Double = 0
    @Published var speed: Double?          // m/s (anlık, yumuşatılmış)
    @Published var accuracy: Double?
    @Published var activities: [Activity] = []
    @Published var route: [CLLocationCoordinate2D] = []

    private let lm = CLLocationManager()
    private var handle: FileHandle?
    private var lastGood: CLLocation?
    private var engine = DistanceEngine(kind: .run)
    private var recent: [CLLocation] = []
    private var lastTick = Date()
    private var timer: Timer?
    private var nextKm = 1
    private var kmMoving: Double = 0
    private let synth = AVSpeechSynthesizer()

    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Aktiviteler", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.distanceFilter = kCLDistanceFilterNone
        lm.pausesLocationUpdatesAutomatically = false
        synth.delegate = self
        load()
        recover()
    }

    // MARK: Sinyal önizleme
    func preview() {
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() }
        lm.startUpdatingLocation()
    }
    func stopPreview() { if state == .idle { lm.stopUpdatingLocation() } }

    // MARK: Kayıt
    func start() {
        guard state == .idle else { return }
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() }
        let a = Activity(id: UUID().uuidString, type: type, start: Date())
        FileManager.default.createFile(atPath: pointsURL(a.id).path, contents: nil)
        handle = try? FileHandle(forWritingTo: pointsURL(a.id))
        engine = DistanceEngine(kind: type.kind)
        current = a; moving = 0; nextKm = 1; kmMoving = 0; route = []; lastGood = nil; autoPaused = false; stillCount = 0; moveCount = 0
        saveMeta(a)
        lm.activityType = type.clType
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = true
        lm.startUpdatingLocation()
        state = .running; lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        say("\(type.name) başladı")
    }
    func pause() { guard state == .running else { return }; tick(); engine.breakSegment(); state = .paused; say("Duraklatıldı") }
    func resume() { guard state == .paused else { return }; lastTick = Date(); lastGood = nil; engine.breakSegment(); state = .running; say("Devam") }

    /// Bitir: GPX yaz, geçmişe ekle. Çok kısa kayıtları atar.
    @discardableResult
    func finish() -> Activity? {
        guard var a = current else { return nil }
        tick()
        timer?.invalidate(); timer = nil
        try? handle?.close(); handle = nil
        lm.allowsBackgroundLocationUpdates = false
        lm.stopUpdatingLocation()
        state = .idle; current = nil; autoPaused = false
        let pts = readPoints(a.id)
        guard pts.count >= 2, !Validity.isTooShort(distance: a.distance, movingTime: moving) else { delete(a); return nil }
        a.end = Date(timeIntervalSince1970: pts.last!.t)
        a.moving = moving
        a.gain = Self.gain(pts)
        a.preview = Self.thumb(pts)
        saveMeta(a); writeGPX(a, pts)
        activities.insert(a, at: 0)
        return a
    }
    func discard() {
        guard let a = current else { return }
        timer?.invalidate(); timer = nil
        try? handle?.close(); handle = nil
        lm.allowsBackgroundLocationUpdates = false; lm.stopUpdatingLocation()
        state = .idle; current = nil
        delete(a)
    }
    func delete(_ a: Activity) {
        for u in [pointsURL(a.id), metaURL(a.id), gpxURL(a)] { try? FileManager.default.removeItem(at: u) }
        activities.removeAll { $0.id == a.id }
    }

    private func tick() {
        let now = Date(), dt = now.timeIntervalSince(lastTick); lastTick = now
        _ = dt   // hareket süresi artık konum zaman damgalarından (DistanceEngine) hesaplanır
    }

    // MARK: Konum
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        for l in locs where l.horizontalAccuracy >= 0 { add(l) }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    private var stillCount = 0, moveCount = 0

    private func add(_ l: CLLocation) {
        accuracy = l.horizontalAccuracy
        recent.append(l); recent.removeAll { l.timestamp.timeIntervalSince($0.timestamp) > 16 }
        var v: Double? = l.speed >= 0 ? l.speed : nil
        if v == nil, let a = recent.first, a !== l {
            let dt = l.timestamp.timeIntervalSince(a.timestamp)
            if dt >= 2 { v = l.distance(from: a) / dt }
        }
        if l.horizontalAccuracy > 50 { v = nil }
        speed = v.map { $0 < type.stopSpeed ? 0 : $0 }

        guard var a = current, let h = handle else { return }
        // Otomatik duraklatma: yalnızca birkaç saniyedir iyi sinyal VE gerçekten yer değiştirmiyorsa
        if !autoPause { autoPaused = false; stillCount = 0; moveCount = 0 }
        else if state == .running, l.horizontalAccuracy <= 30 {
            let win = type.stillWindow
            let old = recent.first { l.timestamp.timeIntervalSince($0.timestamp) <= win && $0.horizontalAccuracy <= 30 }
            if let o = old, l.timestamp.timeIntervalSince(o.timestamp) >= win * 0.8 {
                let net = l.distance(from: o)
                let fast = recent.contains { l.timestamp.timeIntervalSince($0.timestamp) <= win && $0.speed > type.stopSpeed * 1.6 }
                if net < type.stillDist && !fast { stillCount += 1 } else { stillCount = 0 }
            }
            if let x = v, x >= type.stopSpeed * 1.6 { moveCount += 1 } else { moveCount = 0 }
            if !autoPaused, stillCount >= 3 { autoPaused = true; moveCount = 0; engine.breakSegment() }
            if autoPaused, moveCount >= 2 { autoPaused = false; stillCount = 0; lastGood = l; engine.breakSegment() }
        }

        let row = TrackPoint(t: l.timestamp.timeIntervalSince1970, la: l.coordinate.latitude, lo: l.coordinate.longitude,
                             al: l.verticalAccuracy >= 0 ? l.altitude : nil, ha: l.horizontalAccuracy, sp: l.speed >= 0 ? l.speed : nil)
        let recording = state == .running && !(autoPause && autoPaused)
        if recording, let d = try? JSONEncoder().encode(row) { h.write(d); h.write(Data([0x0A])) }
        guard recording else { return }
        let fix = Fix(t: l.timestamp.timeIntervalSince1970, lat: l.coordinate.latitude, lon: l.coordinate.longitude, hAcc: l.horizontalAccuracy, speed: l.speed)
        engine.add(fix)
        a.distance = engine.distance; a.maxSpeed = engine.maxSpeed; moving = engine.movingTime
        if l.horizontalAccuracy <= 30, route.last.map({ CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: l) >= 3 }) ?? true { route.append(l.coordinate) }
        current = a
        if a.distance >= Double(nextKm) * 1000 {
            let ev = max(1, voiceEvery)
            if nextKm % ev == 0 {
                let lap = (moving - kmMoving) / Double(ev); kmMoving = moving
                announce(km: nextKm, lap: lap, a: a)
            }
            nextKm += 1
            saveMeta(a)
        }
    }

    /// Rota küçük resmi için en fazla ~80 nokta
    static func thumb(_ pts: [TrackPoint]) -> [[Double]] {
        let g = pts.filter { $0.ha <= 30 }
        guard g.count > 1 else { return [] }
        let step = max(1, g.count / 80)
        var out = stride(from: 0, to: g.count, by: step).map { [g[$0].la, g[$0].lo] }
        if let l = g.last { out.append([l.la, l.lo]) }
        return out
    }

    // MARK: Ses
    private func announce(km: Int, lap: Double, a: Activity) {
        let s = Int(lap.rounded())
        let msg = type.pace
            ? "\(km) kilometre. Bu kilometre \(s / 60) dakika \(s % 60) saniye."
            : "\(km) kilometre. Ortalama hız \(Int((a.distance / max(1, moving) * 3.6).rounded())) kilometre."
        say(msg)
    }
    private func say(_ s: String) {
        guard voice else { return }
        let ses = AVAudioSession.sharedInstance()
        try? ses.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? ses.setActive(true)
        let u = AVSpeechUtterance(string: s)
        u.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        synth.speak(u)
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        if !s.isSpeaking { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    // MARK: Dosyalar
    func pointsURL(_ id: String) -> URL { Self.dir.appendingPathComponent("\(id).jsonl") }
    private func metaURL(_ id: String) -> URL { Self.dir.appendingPathComponent("\(id).json") }
    func gpxURL(_ a: Activity) -> URL { Self.dir.appendingPathComponent(a.gpxName) }

    func readPoints(_ id: String) -> [TrackPoint] {
        guard let s = try? String(contentsOf: pointsURL(id), encoding: .utf8) else { return [] }
        let d = JSONDecoder()
        return s.split(separator: "\n").compactMap { try? d.decode(TrackPoint.self, from: Data($0.utf8)) }
    }
    private func saveMeta(_ a: Activity) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970
        try? e.encode(a).write(to: metaURL(a.id), options: .atomic)
    }
    private func decodeAll() -> [Activity] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? d.decode(Activity.self, from: Data(contentsOf: $0)) }
    }
    private func load() { activities = decodeAll().filter { $0.end != nil }.sorted { $0.start > $1.start } }
    /// Uygulama kayıt sırasında kapandıysa: yarım aktiviteyi tamamla
    private func recover() {
        for var a in decodeAll() where a.end == nil {
            let pts = readPoints(a.id)
            guard pts.count >= 2 else { delete(a); continue }
            a.end = Date(timeIntervalSince1970: pts.last!.t)
            var dist = 0.0, mv = 0.0
            for i in 1..<pts.count {
                let p = pts[i - 1], q = pts[i], dt = q.t - p.t
                let d = CLLocation(latitude: p.la, longitude: p.lo).distance(from: CLLocation(latitude: q.la, longitude: q.lo))
                if dt < 30, d / max(dt, 0.1) >= a.type.stopSpeed, q.ha <= 30 { dist += d; mv += dt }
            }
            a.distance = dist; a.moving = mv; a.gain = Self.gain(pts); a.preview = Self.thumb(pts)
            saveMeta(a); writeGPX(a, pts); activities.insert(a, at: 0)
        }
        activities.sort { $0.start > $1.start }
    }

    static func gain(_ pts: [TrackPoint]) -> Double {
        let e = pts.compactMap { $0.al }; guard e.count > 10 else { return 0 }
        var sm: [Double] = [], g = 0.0
        for i in e.indices { let a = max(0, i - 5), b = min(e.count - 1, i + 5); sm.append(e[a...b].reduce(0, +) / Double(b - a + 1)) }
        var ref = sm[0]
        for x in sm { if x - ref >= 2 { g += x - ref; ref = x } else if ref - x >= 2 { ref = x } }
        return g
    }

    func gpxText(_ a: Activity) -> String {
        if let s = try? String(contentsOf: gpxURL(a), encoding: .utf8) { return s }
        return makeGPX(a, readPoints(a.id))
    }
    private func writeGPX(_ a: Activity, _ pts: [TrackPoint]) {
        try? makeGPX(a, pts).write(to: gpxURL(a), atomically: true, encoding: .utf8)
    }
    private func makeGPX(_ a: Activity, _ pts: [TrackPoint]) -> String {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TelemetriGo iOS Aktivite" xmlns="http://www.topografix.com/GPX/1/1" xmlns:tg="https://rahimov0.github.io/-telemetrigo-/gpx/1">
        <metadata><name>\(a.type.title(a.start))</name><time>\(iso.string(from: a.start))</time></metadata>
        <trk><name>\(a.type.title(a.start))</name><type>\(a.type.rawValue)</type><trkseg>

        """
        for p in pts {
            s += "<trkpt lat=\"\(p.la)\" lon=\"\(p.lo)\">"
            if let al = p.al { s += "<ele>\(String(format: "%.1f", al))</ele>" }
            s += "<time>\(iso.string(from: Date(timeIntervalSince1970: p.t)))</time><extensions>"
            if let sp = p.sp { s += "<tg:speed>\(String(format: "%.2f", sp))</tg:speed>" }
            s += "<tg:hacc>\(String(format: "%.1f", p.ha))</tg:hacc></extensions></trkpt>\n"
        }
        return s + "</trkseg></trk></gpx>\n"
    }
}
