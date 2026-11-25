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
        let title = UILabel(); title.text = "Video hazırlanıyor"; title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let note = UILabel(); note.text = "Ekranı kapatma, uygulamadan çıkma"; note.textColor = UIColor.white.withAlphaComponent(0.7)
        note.font = .systemFont(ofSize: 13, weight: .medium)
        let cancel = UIButton(type: .system)
        cancel.setTitle("İptal", for: .normal)
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

/// Flyover'ı ekran kaydı izni olmadan videoya çevirir: her kareyi sırayla çizdirir, ekrandan alır ve H.264 olarak yazar.
@MainActor
enum FlyoverExporter {
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
    }

    /// `step(i)` i. kare için sahneyi ayarlar. Haritanın karoları yüklenebilsin diye her kareden önce kısa beklenir.
    static func render(frames: Int, fps: Int, wait: UInt64 = 300_000_000,
                       step: (Int) -> Void, progress: (Int) -> Void, cancelled: () -> Bool) async throws -> URL {
        guard let win = keyWindow else { throw ExportError(msg: "Ekran bulunamadı.") }
        let scale = min(win.screen.scale, 2)
        let w = Int(win.bounds.width * scale) & ~1, h = Int(win.bounds.height * scale) & ~1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KROVA-Flyover-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 9_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h
        ])
        guard writer.canAdd(input) else { throw ExportError(msg: "Video yazıcı başlatılamadı.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError(msg: "Video yazıcı başlatılamadı.") }
        writer.startSession(atSourceTime: .zero)

        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = scale; fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: win.bounds.size, format: fmt)
        let space = CGColorSpaceCreateDeviceRGB()

        step(0)
        try await Task.sleep(nanoseconds: 1_500_000_000)   // ilk görüntünün karoları yüklensin
        for i in 0..<frames {
            if cancelled() { writer.cancelWriting(); throw CancellationError() }
            if UIApplication.shared.applicationState != .active {
                writer.cancelWriting()
                throw ExportError(msg: "Uygulamadan çıkıldığı veya ekran kapandığı için kayıt iptal edildi. Tekrar dene ve ekranı açık tut.")
            }
            step(i)
            try await Task.sleep(nanoseconds: wait)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            let img = renderer.image { _ in win.drawHierarchy(in: win.bounds, afterScreenUpdates: true) }
            var pbOut: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pbOut)
            guard let pb = pbOut, let cg = img.cgImage else { throw ExportError(msg: "Kare oluşturulamadı.") }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            if !adaptor.append(pb, withPresentationTime: CMTime(value: Int64(i), timescale: Int32(fps))) {
                throw writer.error ?? ExportError(msg: "Kare yazılamadı.")
            }
            progress(i + 1)
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ExportError(msg: "Video tamamlanamadı.") }
        return url
    }
}
