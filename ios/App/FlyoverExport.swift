import UIKit
import AVFoundation

struct ExportError: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

/// Dışa aktarma sırasında ekranın ortasında görünen büyük yüzde (ayrı pencere: karelere girmez)
@MainActor
final class ExportOverlay {
    private let window: UIWindow
    private let pct = UILabel()
    var onCancel: () -> Void = {}

    init?() {
        guard let sc = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        let b = sc.screen.bounds, w: CGFloat = min(b.width - 48, 300), h: CGFloat = 230
        window = UIWindow(windowScene: sc)
        window.frame = CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let vc = UIViewController()
        vc.view.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        vc.view.layer.cornerRadius = 28
        pct.textColor = .white
        pct.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        pct.text = "%0"
        let title = UILabel(); title.text = L("Video hazırlanıyor"); title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let note = UILabel(); note.text = L("Ekranı kapatma, uygulamadan çıkma"); note.textColor = UIColor.white.withAlphaComponent(0.7)
        note.font = .systemFont(ofSize: 13, weight: .medium)
        let cancel = UIButton(type: .system)
        cancel.setTitle(L("İptal"), for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancel.tintColor = UIColor(red: 1, green: 0.353, blue: 0.122, alpha: 1)
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel() }, for: .touchUpInside)
        let col = UIStackView(arrangedSubviews: [title, pct, note, cancel])
        col.axis = .vertical; col.alignment = .center; col.spacing = 6
        col.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(col)
        NSLayoutConstraint.activate([
            col.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            col.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)
        ])
        window.rootViewController = vc
        window.isHidden = false
    }
    func update(_ p: Int) { pct.text = "%\(p)" }
    func close() { window.isHidden = true }
}

/// Videonun bir parçası (en fazla ~90 kare). Uygulama arka plana gidip yazıcı bozulursa yalnızca bu parça yeniden çizilir.
private final class VideoSegment {
    let url: URL, writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor
    let startFrame: Int
    var count = 0
    init(w: Int, h: Int, startFrame: Int) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("KROVA-seg-\(UUID().uuidString).mp4")
        writer = try AVAssetWriter(url: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 9_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h
        ])
        self.startFrame = startFrame
        guard writer.canAdd(input) else { throw ExportError(msg: L("Video yazıcı başlatılamadı.")) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError(msg: L("Video yazıcı başlatılamadı.")) }
        writer.startSession(atSourceTime: .zero)
    }
    func discard() { writer.cancelWriting(); try? FileManager.default.removeItem(at: url) }
    /// true: parça sağlam bitti
    func finish() async -> Bool {
        guard writer.status == .writing else { return false }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }
}

/// Flyover'ı ekran kaydı izni olmadan videoya çevirir: her kareyi sırayla çizdirir, ekrandan alır ve H.264 parçaları olarak yazar, sonda birleştirir.
@MainActor
enum FlyoverExporter {
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow && $0.windowLevel == .normal }
    }

    /// `step(i)` i. kare için sahneyi ayarlar. Haritanın karoları yüklenebilsin diye her kareden önce kısa beklenir.
    static func render(frames: Int, fps: Int, wait: UInt64 = 300_000_000,
                       step: (Int) -> Void, progress: (Int) -> Void, cancelled: () -> Bool) async throws -> URL {
        guard let win = keyWindow else { throw ExportError(msg: L("Ekran bulunamadı.")) }
        let scale = min(win.screen.scale, 2)
        let w = Int(win.bounds.width * scale) & ~1, h = Int(win.bounds.height * scale) & ~1
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = scale; fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: win.bounds.size, format: fmt)
        let space = CGColorSpaceCreateDeviceRGB()
        let segLimit = 90
        var done: [URL] = []
        var seg: VideoSegment?
        var failures = 0
        func cleanup() { seg?.discard(); done.forEach { try? FileManager.default.removeItem(at: $0) } }

        step(0)
        try await Task.sleep(nanoseconds: 1_500_000_000)   // ilk görüntünün karoları yüklensin
        var i = 0
        do {
            while i < frames {
                if cancelled() { throw CancellationError() }
                // Uygulamadan çıkılırsa (arama, bildirim merkezi, kilit) duraklar, geri dönünce sürer
                if UIApplication.shared.applicationState != .active {
                    let t0 = Date()
                    while UIApplication.shared.applicationState != .active {
                        if cancelled() { throw CancellationError() }
                        if Date().timeIntervalSince(t0) > 600 { throw ExportError(msg: L("Uygulamaya 10 dakikadır dönülmediği için kayıt iptal edildi.")) }
                        try await Task.sleep(nanoseconds: 300_000_000)
                    }
                    try await Task.sleep(nanoseconds: 900_000_000)   // geri dönünce harita kendine gelsin
                    // arka plandan dönüşte yazıcı bozulmuş olabilir: parçayı baştan başlat
                    if let s = seg, s.writer.status != .writing { s.discard(); i = s.startFrame; seg = nil }
                }
                step(i)
                try await Task.sleep(nanoseconds: wait)
                let img = renderer.image { _ in win.drawHierarchy(in: win.bounds, afterScreenUpdates: true) }
                var pbOut: CVPixelBuffer?
                CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pbOut)
                guard let pb = pbOut, let cg = img.cgImage else { throw ExportError(msg: L("Kare oluşturulamadı.")) }
                CVPixelBufferLockBaseAddress(pb, [])
                if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: space,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
                CVPixelBufferUnlockBaseAddress(pb, [])

                let s: VideoSegment
                if let cur = seg { s = cur } else { s = try VideoSegment(w: w, h: h, startFrame: i); seg = s }
                while !s.input.isReadyForMoreMediaData && s.writer.status == .writing { try await Task.sleep(nanoseconds: 10_000_000) }
                let ok = s.writer.status == .writing && s.adaptor.append(pb, withPresentationTime: CMTime(value: Int64(s.count), timescale: Int32(fps)))
                if !ok {
                    // yazıcı bozuldu: bu parçayı at, parçanın ilk karesinden yeniden çiz
                    failures += 1
                    if failures > 8 { throw s.writer.error ?? ExportError(msg: L("Video yazılamadı. Uygulamayı açık tutup tekrar dene.")) }
                    s.discard(); i = s.startFrame; seg = nil
                    continue
                }
                s.count += 1; i += 1
                progress(i)
                if s.count >= segLimit {
                    seg = nil
                    if await s.finish() { done.append(s.url) }
                    else {
                        failures += 1
                        if failures > 8 { throw s.writer.error ?? ExportError(msg: L("Video yazılamadı.")) }
                        s.discard(); i = s.startFrame
                    }
                }
            }
            if let s = seg {
                seg = nil
                if await s.finish() { done.append(s.url) }
                else { s.discard(); throw s.writer.error ?? ExportError(msg: L("Video tamamlanamadı.")) }
            }
        } catch {
            cleanup(); throw error
        }
        return try await merge(done)
    }

    /// Parçaları kayıpsız tek MP4'e birleştirir
    private static func merge(_ urls: [URL]) async throws -> URL {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("KROVA-Flyover-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: out)
        if urls.count == 1 { try FileManager.default.moveItem(at: urls[0], to: out); return out }
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError(msg: L("Parçalar birleştirilemedi."))
        }
        var t = CMTime.zero
        for u in urls {
            let a = AVURLAsset(url: u)
            guard let vt = try await a.loadTracks(withMediaType: .video).first else { continue }
            let d = try await a.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: vt, at: t)
            t = CMTimeAdd(t, d)
        }
        guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { throw ExportError(msg: L("Birleştirici başlatılamadı.")) }
        ex.outputURL = out; ex.outputFileType = .mp4
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in ex.exportAsynchronously { c.resume() } }
        urls.forEach { try? FileManager.default.removeItem(at: $0) }
        if ex.status != .completed { throw ex.error ?? ExportError(msg: L("Parçalar birleştirilemedi.")) }
        return out
    }
}
