import SwiftUI
import PhotosUI
import ImageIO

/// Profilde gösterilen paylaşım (Stüdyo/fotoğraf editöründen dışa aktarılan görsel)
struct ProfilePost: Codable, Identifiable, Hashable {
    var id: String
    var file: String          // Documents/Profil altındaki dosya adı
    var date: Date
    var title: String
    var type: String          // aktivite türü anahtarı
}

/// Yerel profil: ad, fotoğraf ve paylaşılan görsellerin galerisi (hesap/sunucu yok, yalnızca bu cihazda)
final class ProfileStore: ObservableObject {
    @Published var name: String = UserDefaults.standard.string(forKey: "profName") ?? "" { didSet { UserDefaults.standard.set(name, forKey: "profName") } }
    @Published var posts: [ProfilePost] = []
    @Published var avatar: UIImage?

    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Profil", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var indexURL: URL { Self.dir.appendingPathComponent("gonderiler.json") }
    private var avatarURL: URL { Self.dir.appendingPathComponent("avatar.jpg") }

    init() {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        if let data = try? Data(contentsOf: indexURL), let p = try? d.decode([ProfilePost].self, from: data) {
            posts = p.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        }
        avatar = UIImage(contentsOfFile: avatarURL.path)
    }

    func url(for p: ProfilePost) -> URL { Self.dir.appendingPathComponent(p.file) }

    /// Dışa aktarılan görseli galeriye kopyalar (video dosyaları eklenmez)
    func add(imageAt src: URL, title: String, type: String) {
        let ext = src.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "heic"].contains(ext) else { return }
        let id = UUID().uuidString
        let file = "\(id).\(ext)"
        do { try FileManager.default.copyItem(at: src, to: Self.dir.appendingPathComponent(file)) } catch { return }
        DispatchQueue.main.async {
            self.posts.insert(ProfilePost(id: id, file: file, date: Date(), title: title, type: type), at: 0)
            self.save()
        }
    }

    /// Editörden gelen görseli (ham veri) galeriye ekler
    func add(data: Data, ext: String, title: String, type: String) {
        let id = UUID().uuidString, file = "\(id).\(ext == "png" ? "png" : "jpg")"
        do { try data.write(to: Self.dir.appendingPathComponent(file), options: .atomic) } catch { return }
        DispatchQueue.main.async {
            self.posts.insert(ProfilePost(id: id, file: file, date: Date(), title: title, type: type), at: 0)
            self.save()
        }
    }

    func delete(_ p: ProfilePost) {
        try? FileManager.default.removeItem(at: url(for: p))
        posts.removeAll { $0.id == p.id }
        save()
    }

    func setAvatar(_ img: UIImage) {
        let side: CGFloat = 400
        let r = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * r, height: img.size.height * r)
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        try? small.jpegData(compressionQuality: 0.85)?.write(to: avatarURL, options: .atomic)
        avatar = small
    }

    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970
        try? e.encode(posts).write(to: indexURL, options: .atomic)
    }

    /// Izgara için küçültülmüş önizleme
    static func thumbnail(_ url: URL, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

struct ProfileTab: View {
    @ObservedObject var act: ActivityRecorder
    @ObservedObject var health: HealthManager
    @ObservedObject var store: ProfileStore
    @State private var pick: PhotosPickerItem?
    @State private var open: ProfilePost?

    private var totalKm: Double { act.activities.reduce(0) { $0 + $1.distance } / 1000 }
    private let cols = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                stats
                gallery
            }
            .padding(.horizontal, 16).padding(.top, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $open) { p in PostDetail(store: store, post: p) }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await MainActor.run { store.setAvatar(img) }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $pick, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let a = store.avatar { Image(uiImage: a).resizable().scaledToFill() }
                        else { Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(Theme.text3).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.card) }
                    }
                    .frame(width: 96, height: 96).clipShape(Circle())
                    Image(systemName: "camera.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onAcc)
                        .frame(width: 28, height: 28).background(Theme.acc, in: Circle()).overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                }
            }.accessibilityLabel("Profil fotoğrafını değiştir")
            TextField("Adını yaz", text: $store.name)
                .font(.title3.weight(.bold)).multilineTextAlignment(.center).foregroundStyle(Theme.text)
                .submitLabel(.done)
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(Fmt.num(Double(store.posts.count)), "paylaşım")
            stat(Fmt.num(Double(act.activities.count)), "aktivite")
            stat(Fmt.num(totalKm, 0), "km")
        }
        .padding(.vertical, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
            Text(l).font(.caption).foregroundStyle(Theme.text2)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private var gallery: some View {
        if store.posts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(Theme.text3)
                Text("Henüz paylaşım yok").font(.headline).foregroundStyle(Theme.text)
                Text("Bir aktiviteyi fotoğrafa ekleyip Paylaş'a bastığında görsel burada birikir.")
                    .font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            }.padding(.vertical, 40).padding(.horizontal, 20)
        } else {
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(store.posts) { p in
                    Button { open = p } label: { PostThumb(url: store.url(for: p)) }.buttonStyle(.plain)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct PostThumb: View {
    let url: URL
    @State private var img: UIImage?
    var body: some View {
        Color(Theme.card).aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let img {
                    // Hiçbir paylaşım kırpılmaz: bulanık arka plan + tam görüntü; böylece hepsi aynı ölçekte ve eksiksiz görünür
                    ZStack {
                        Image(uiImage: img).resizable().scaledToFill().blur(radius: 14).opacity(0.75)
                        Image(uiImage: img).resizable().scaledToFit()
                    }
                }
            }
            .clipped()
            .task { img = await Task.detached { ProfileStore.thumbnail(url, maxPixel: 500) }.value }
    }
}

struct PostDetail: View {
    @ObservedObject var store: ProfileStore
    let post: ProfilePost
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Theme.text3.opacity(0.5)).frame(width: 36, height: 5).padding(.top, 8)
            if let img = UIImage(contentsOfFile: store.url(for: post).path) {
                Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(spacing: 2) {
                Text(post.title).font(.headline).foregroundStyle(Theme.text)
                Text(post.date.formatted(.dateTime.day().month(.wide).year().hour().minute())).font(.subheadline).foregroundStyle(Theme.text2)
            }
            HStack(spacing: 12) {
                ShareLink(item: store.url(for: post)) { Label("Paylaş", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(GhostButton(height: 50))
                Button(role: .destructive) { confirm = true } label: { Label("Sil", systemImage: "trash").frame(maxWidth: .infinity) }
                    .buttonStyle(GhostButton(height: 50))
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .background(Theme.bg.ignoresSafeArea())
        .confirmationDialog("Bu paylaşım profilinden silinsin mi? (Fotoğraflar'a kaydettiysen oradaki kopya silinmez.)", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { store.delete(post); dismiss() }
        }
    }
}
