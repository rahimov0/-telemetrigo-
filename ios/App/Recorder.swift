import Foundation
import CoreLocation

/// Kaydedilen bir sürüş
struct Session: Codable, Identifiable, Hashable {
    var id: String
    var start: Date
    var end: Date?
    var points: Int = 0
    var distance: Double = 0      // m
    var maxSpeed: Double = 0      // m/s
    var camEvents: [CamEvent] = []
    var gpxName: String { "TelemetriGo_\(Self.nameFmt.string(from: start)).gpx" }
    static let nameFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
}
struct CamEvent: Codable, Hashable { var type: String; var time: Date }   // camstart / camstop

/// Arka planda (ekran kilitliyken de) çalışan GPS kaydedici. Her nokta anında diske yazılır.
final class Recorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var auth: CLAuthorizationStatus = .notDetermined
    @Published var accuracy: Double?          // m
    @Published var speed: Double?             // m/s, duruş eşiği uygulanmış
    @Published var current: Session?          // kayıt sürüyorsa
    @Published var sessions: [Session] = []

    private let lm = CLLocationManager()
    private var handle: FileHandle?
    private var last: CLLocation?
    private var recent: [CLLocation] = []

    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Kayitlar", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.distanceFilter = kCLDistanceFilterNone
        lm.activityType = .otherNavigation
        lm.pausesLocationUpdatesAutomatically = false
        auth = lm.authorizationStatus
        load()
        recoverUnfinished()
    }

    // MARK: İzleme (kayıt dışında da sinyal kalitesini göstermek için)
    func startPreview() {
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() }
        lm.startUpdatingLocation()
    }
    func stopPreviewIfIdle() { if current == nil { lm.stopUpdatingLocation() } }

    // MARK: Kayıt
    func start() {
        guard current == nil else { return }
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() }
        let s = Session(id: UUID().uuidString, start: Date())
        let url = pointsURL(s.id)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        current = s; last = nil
        saveMeta(s)
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = true
        lm.startUpdatingLocation()
    }
    func stop() {
        guard var s = current else { return }
        s.end = Date()
        try? handle?.close(); handle = nil
        lm.allowsBackgroundLocationUpdates = false
        current = nil
        saveMeta(s)
        writeGPX(s)
        sessions.insert(s, at: 0)
    }
    func mark(_ type: String, at t: Date) {
        guard current != nil else { return }
        current?.camEvents.append(CamEvent(type: type, time: t))
        if let s = current { saveMeta(s) }
    }
    func delete(_ s: Session) {
        for u in [pointsURL(s.id), metaURL(s.id), gpxURL(s)] { try? FileManager.default.removeItem(at: u) }
        sessions.removeAll { $0.id == s.id }
    }

    // MARK: CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { auth = m.authorizationStatus }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        for l in locs where l.horizontalAccuracy >= 0 { add(l) }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    private func add(_ l: CLLocation) {
        accuracy = l.horizontalAccuracy
        recent.append(l); recent.removeAll { l.timestamp.timeIntervalSince($0.timestamp) > 4 }
        // canlı hız: Doppler hızı; yoksa son 4 sn'deki net yer değiştirme. Duruşta 0.
        var v: Double? = l.speed >= 0 ? l.speed : nil
        if v == nil, let a = recent.first, a !== l {
            let dt = l.timestamp.timeIntervalSince(a.timestamp), d = l.distance(from: a)
            v = dt >= 1 ? (d > max(a.horizontalAccuracy, l.horizontalAccuracy) ? d / dt : 0) : nil
        }
        if l.horizontalAccuracy > 50 { v = nil } else if let x = v, x < 0.9 { v = 0 }
        speed = v

        guard var s = current, let h = handle else { return }
        if let p = last, l.timestamp <= p.timestamp { return }
        if let p = last, (v ?? 0) > 0, l.horizontalAccuracy <= 50 { s.distance += l.distance(from: p) }
        if let x = v { s.maxSpeed = max(s.maxSpeed, x) }
        s.points += 1
        last = l
        let row: [String: Any?] = [
            "t": l.timestamp.timeIntervalSince1970, "la": l.coordinate.latitude, "lo": l.coordinate.longitude,
            "al": l.verticalAccuracy >= 0 ? l.altitude : nil, "ha": l.horizontalAccuracy, "va": l.verticalAccuracy >= 0 ? l.verticalAccuracy : nil,
            "sp": l.speed >= 0 ? l.speed : nil, "sa": l.speedAccuracy >= 0 ? l.speedAccuracy : nil, "co": l.course >= 0 ? l.course : nil]
        if let d = try? JSONSerialization.data(withJSONObject: row.compactMapValues { $0 }) { h.write(d); h.write(Data([0x0A])) }
        current = s
        if s.points % 10 == 0 { saveMeta(s) }
    }

    // MARK: Dosyalar
    private func pointsURL(_ id: String) -> URL { Self.dir.appendingPathComponent("\(id).jsonl") }
    private func metaURL(_ id: String) -> URL { Self.dir.appendingPathComponent("\(id).json") }
    func gpxURL(_ s: Session) -> URL { Self.dir.appendingPathComponent(s.gpxName) }

    private func saveMeta(_ s: Session) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970
        try? e.encode(s).write(to: metaURL(s.id), options: .atomic)
    }
    private func load() {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        sessions = files.filter { $0.pathExtension == "json" }
            .compactMap { try? d.decode(Session.self, from: Data(contentsOf: $0)) }
            .filter { $0.end != nil }
            .sorted { $0.start > $1.start }
    }
    /// Uygulama kayıt sırasında kapandıysa yarım kaydı tamamla
    private func recoverUnfinished() {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            guard var s = try? d.decode(Session.self, from: Data(contentsOf: f)), s.end == nil else { continue }
            let rows = readRows(s.id)
            guard let lastT = rows.last?["t"] as? Double else { delete(s); continue }
            s.end = Date(timeIntervalSince1970: lastT); s.points = rows.count
            saveMeta(s); writeGPX(s); sessions.insert(s, at: 0)
        }
        sessions.sort { $0.start > $1.start }
    }
    private func readRows(_ id: String) -> [[String: Any]] {
        guard let txt = try? String(contentsOf: pointsURL(id), encoding: .utf8) else { return [] }
        return txt.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    func gpxText(_ s: Session) -> String {
        if !FileManager.default.fileExists(atPath: gpxURL(s).path) { writeGPX(s) }
        return (try? String(contentsOf: gpxURL(s), encoding: .utf8)) ?? ""
    }
    private func writeGPX(_ s: Session) {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = readRows(s.id)
        func n(_ v: Any?, _ d: Int) -> String? { (v as? Double).map { String(format: "%.\(d)f", $0) } }
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TelemetriGo iOS" xmlns="http://www.topografix.com/GPX/1/1" xmlns:tg="https://telemetrigo.rahimov.tr/gpx/1">
        <metadata><name>TelemetriGo</name><time>\(iso.string(from: s.start))</time></metadata>

        """
        let ref = rows.last
        for e in s.camEvents {
            out += "<wpt lat=\"\(n(ref?["la"], 7) ?? "0")\" lon=\"\(n(ref?["lo"], 7) ?? "0")\"><time>\(iso.string(from: e.time))</time><name>\(e.type)</name><type>tg:\(e.type)</type></wpt>\n"
        }
        out += "<trk><name>TelemetriGo</name><trkseg>\n"
        for r in rows {
            guard let t = r["t"] as? Double, let la = n(r["la"], 7), let lo = n(r["lo"], 7) else { continue }
            out += "<trkpt lat=\"\(la)\" lon=\"\(lo)\">"
            if let al = n(r["al"], 1) { out += "<ele>\(al)</ele>" }
            out += "<time>\(iso.string(from: Date(timeIntervalSince1970: t)))</time><extensions>"
            if let sp = n(r["sp"], 2) { out += "<tg:speed>\(sp)</tg:speed>" }
            if let sa = n(r["sa"], 2) { out += "<tg:sacc>\(sa)</tg:sacc>" }
            if let co = n(r["co"], 1) { out += "<tg:course>\(co)</tg:course>" }
            if let ha = n(r["ha"], 1) { out += "<tg:hacc>\(ha)</tg:hacc>" }
            if let va = n(r["va"], 1) { out += "<tg:vacc>\(va)</tg:vacc>" }
            out += "</extensions></trkpt>\n"
        }
        out += "</trkseg></trk></gpx>\n"
        try? out.write(to: gpxURL(s), atomically: true, encoding: .utf8)
    }
}
