import Foundation
import CoreBluetooth

/// Open GoPro BLE: HERO9 ve sonrası. Kamera ilk seferde "Kablosuz Bağlantılar → Cihaz Bağla → GoPro Quik"
/// eşleşme modunda olmalı; sonra kayıtlı kameraya otomatik yeniden bağlanılır.
/// Belge: https://gopro.github.io/OpenGoPro/ble
final class GoProManager: NSObject, ObservableObject {
    enum Phase: Equatable { case off, idle, scanning, connecting, ready, failed(String) }

    @Published var phase: Phase = .idle
    @Published var name: String = ""
    @Published var battery: Int?          // %
    @Published var encoding = false       // kamera şu an kayıt yapıyor mu
    @Published var recSeconds: Int = 0    // kameranın bildirdiği kayıt süresi
    @Published var bluetoothOn = true
    @Published var lastError: String?

    /// Kayıt başlangıç/bitiş anları (telefon saatiyle, ms hassasiyetinde)
    var onEncodingChange: ((Bool, Date) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var keepAlive: Timer?
    private var poll: Timer?
    private var wantConnect = false
    private var rx: [CBUUID: (len: Int, data: Data)] = [:]
    private var pendingShutter: ((Bool) -> Void)?

    private static let service = CBUUID(string: "FEA6")
    private static func gp(_ s: String) -> CBUUID { CBUUID(string: "b5f9\(s)-aa8d-11e3-9046-0002a5d5c51b") }
    private static let cmd = gp("0072"), cmdResp = gp("0073")
    private static let setting = gp("0074"), settingResp = gp("0075")
    private static let query = gp("0076"), queryResp = gp("0077")
    private static let savedKey = "gopro.peripheral"

    // Durum kimlikleri (Open GoPro)
    private static let stEncoding: UInt8 = 10, stProgress: UInt8 = 13, stBattery: UInt8 = 70

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    var isReady: Bool { phase == .ready }
    var hasSavedCamera: Bool { UserDefaults.standard.string(forKey: Self.savedKey) != nil }

    // MARK: Bağlantı
    func connect() {
        wantConnect = true; lastError = nil
        guard central.state == .poweredOn else { phase = .off; return }
        if let s = UserDefaults.standard.string(forKey: Self.savedKey), let id = UUID(uuidString: s),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            open(p)
        }
        // kayıtlı kamera kapalı/uzaksa reklam yayınını da dinle
        if phase != .connecting {
            phase = .scanning
            central.scanForPeripherals(withServices: [Self.service], options: nil)
        }
    }
    func disconnect() {
        wantConnect = false
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        cleanup(); phase = .idle
    }
    func forget() { UserDefaults.standard.removeObject(forKey: Self.savedKey); disconnect(); name = "" }

    private func open(_ p: CBPeripheral) {
        central.stopScan()
        peripheral = p; p.delegate = self
        phase = .connecting
        central.connect(p, options: nil)
    }
    private func cleanup() {
        keepAlive?.invalidate(); keepAlive = nil; poll?.invalidate(); poll = nil
        chars = [:]; rx = [:]; peripheral = nil; battery = nil
        if encoding { encoding = false; onEncodingChange?(false, Date()) }
    }

    // MARK: Komutlar
    /// Kaydı başlat/durdur. Tamamlandığında kameranın onayı döner.
    func shutter(_ on: Bool, done: ((Bool) -> Void)? = nil) {
        pendingShutter = done
        send(Self.cmd, [0x01, 0x01, on ? 0x01 : 0x00])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.requestStatus() }
    }
    /// Kameranın saatini telefona eşitle (yerel saat + saat dilimi)
    func syncClock() {
        let now = Date(), cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents(in: TimeZone.current, from: now)
        let y = UInt16(c.year ?? 2026)
        let tz = Int16(TimeZone.current.secondsFromGMT(for: now) / 60) - Int16(TimeZone.current.isDaylightSavingTime(for: now) ? 60 : 0)
        let dst: UInt8 = TimeZone.current.isDaylightSavingTime(for: now) ? 1 : 0
        let base: [UInt8] = [UInt8(y >> 8), UInt8(y & 0xFF), UInt8(c.month ?? 1), UInt8(c.day ?? 1), UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0)]
        // 0x0F: yerel saat + UTC farkı + yaz saati (HERO10+). Desteklenmezse 0x0D ile sadece saat
        let tzHi = UInt8(truncatingIfNeeded: tz >> 8), tzLo = UInt8(truncatingIfNeeded: tz)
        var msg: [UInt8] = [0x0F, 0x0A]
        msg.append(contentsOf: base)
        msg.append(contentsOf: [tzHi, tzLo, dst])
        send(Self.cmd, msg)
    }
    private func syncClockFallback() {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: Date())
        let y = UInt16(c.year ?? 2026)
        send(Self.cmd, [0x0D, 0x07, UInt8(y >> 8), UInt8(y & 0xFF), UInt8(c.month ?? 1), UInt8(c.day ?? 1), UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0)])
    }
    private func requestStatus() { send(Self.query, [0x13, Self.stEncoding, Self.stProgress, Self.stBattery]) }

    /// Kısa mesajlar (<= 19 bayt yük) için genel 5 bitlik başlık
    private func send(_ uuid: CBUUID, _ payload: [UInt8]) {
        guard let p = peripheral, let c = chars[uuid], payload.count < 20 else { return }
        p.writeValue(Data([UInt8(payload.count)] + payload), for: c, type: .withResponse)
    }

    private func didBecomeReady() {
        phase = .ready
        if let p = peripheral { UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedKey); name = p.name ?? "GoPro" }
        send(Self.cmd, [0x50])                          // üçüncü taraf istemci olduğumuzu bildir
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.syncClock() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }            // kayıt ve pil değişince bildirim gelsin
            self.send(Self.query, [0x53, Self.stEncoding, Self.stBattery])
        }
        keepAlive = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.send(Self.setting, [0x5B, 0x01, 0x42])
        }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.encoding else { return }
            self.send(Self.query, [0x13, Self.stProgress])
        }
    }

    // MARK: Yanıtlar
    private func handle(_ msg: Data, from uuid: CBUUID) {
        let b = [UInt8](msg); guard b.count >= 2 else { return }
        if uuid == Self.cmdResp {
            let id = b[0], ok = b[1] == 0
            if id == 0x01 { pendingShutter?(ok); pendingShutter = nil; if !ok { lastError = "GoPro kayıt komutunu reddetti (kart dolu/yok ya da kamera meşgul olabilir)." } }
            if id == 0x0F && !ok { syncClockFallback() }
            return
        }
        if uuid == Self.queryResp {
            // [komut, durum, (id, uzunluk, değer)…]; 0x93 = abone olunan durum değişti
            guard [0x13, 0x53, 0x93].contains(b[0]), b[1] == 0 else { return }
            var i = 2
            while i + 1 < b.count {
                let id = b[i], len = Int(b[i + 1]); i += 2
                guard i + len <= b.count else { break }
                var v = 0; for k in 0..<len { v = (v << 8) | Int(b[i + k]) }
                i += len
                switch id {
                case Self.stEncoding:
                    let now = v == 1
                    if now != encoding { encoding = now; if !now { recSeconds = 0 }; onEncodingChange?(now, Date()) }
                case Self.stProgress: recSeconds = v
                case Self.stBattery: battery = v
                default: break
                }
            }
        }
    }

    /// GoPro paketlerini birleştirir (başlık: genel 5 bit, genişletilmiş 13/16 bit, devam paketleri)
    private func reassemble(_ data: Data, _ uuid: CBUUID) -> Data? {
        let b = [UInt8](data); guard !b.isEmpty else { return nil }
        if b[0] & 0x80 != 0 {
            guard var cur = rx[uuid] else { return nil }
            cur.data.append(contentsOf: b.dropFirst()); rx[uuid] = cur
        } else {
            switch (b[0] >> 5) & 0x03 {
            case 0: rx[uuid] = (Int(b[0] & 0x1F), Data(b.dropFirst(1)))
            case 1: guard b.count >= 2 else { return nil }; rx[uuid] = ((Int(b[0] & 0x1F) << 8) | Int(b[1]), Data(b.dropFirst(2)))
            case 2: guard b.count >= 3 else { return nil }; rx[uuid] = ((Int(b[1]) << 8) | Int(b[2]), Data(b.dropFirst(3)))
            default: return nil
            }
        }
        guard let cur = rx[uuid], cur.data.count >= cur.len else { return nil }
        rx[uuid] = nil
        return cur.data.prefix(cur.len)
    }
}

extension GoProManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        bluetoothOn = c.state == .poweredOn
        if c.state == .poweredOn { if wantConnect || hasSavedCamera { connect() } else { phase = .idle } }
        else { cleanup(); phase = .off }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard phase == .scanning else { return }
        open(p)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices(nil)
    }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        cleanup(); phase = .failed("Bağlanılamadı: \(error?.localizedDescription ?? "bilinmeyen hata")")
        if wantConnect { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in if self?.wantConnect == true { self?.connect() } } }
    }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        let wasReady = phase == .ready
        cleanup()
        if wantConnect {
            phase = .scanning
            if wasReady { lastError = "GoPro bağlantısı koptu, yeniden bağlanılıyor…" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in if self?.wantConnect == true { self?.connect() } }
        } else { phase = .idle }
    }
}

extension GoProManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            chars[c.uuid] = c
            if [Self.cmdResp, Self.settingResp, Self.queryResp].contains(c.uuid) { p.setNotifyValue(true, for: c) }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let error {
            // şifreli özellik: eşleşme yoksa burada hata gelir
            phase = .failed("Eşleşme gerekli. GoPro'da: Tercihler → Kablosuz Bağlantılar → Cihaz Bağla → GoPro Quik. (\(error.localizedDescription))")
            return
        }
        let need = [Self.cmdResp, Self.settingResp, Self.queryResp]
        if phase != .ready, need.allSatisfy({ chars[$0]?.isNotifying == true }), chars[Self.cmd] != nil { didBecomeReady() }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let v = c.value, let msg = reassemble(v, c.uuid) else { return }
        handle(msg, from: c.uuid)
    }
}
