import SwiftUI
import KrovaCore

/// Stüdyo: aktiviteden paylaşılabilir görsel + videoya telemetri. Düzenleme motorları web tabanlıdır; bu ekran onları tek yerde toplar.
struct StudioTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var act: ActivityRecorder
    @State private var mode = 0                 // 0 görsel, 1 video
    @State private var editing: Activity?
    @State private var showVideo = false
    @State private var showCam = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Stüdyo").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                    Spacer()
                }
                HStack(spacing: 2) {
                    seg("Görsel", 0); seg("Video", 1)
                }.padding(3).background(Theme.card, in: Capsule())
                if mode == 0 { imageMode } else { videoMode }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $editing) { a in
            PhotoEditorSheet(gpx: act.gpxText(a), name: a.type.title(a.start), type: a.type.rawValue, steps: nil, kcal: Cal.active(a))
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $showVideo) {
            VStack(spacing: 0) {
                HStack {
                    Button { showVideo = false } label: {
                        Text("Kapat").font(.body.weight(.medium)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 34)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    Text("Video").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 66, height: 1)
                }.padding(.horizontal, 16).padding(.vertical, 8)
                VideoTab().environmentObject(model)
            }.background(Color.black.ignoresSafeArea())
        }
        .sheet(isPresented: $showCam) { RecordView().environmentObject(model) }
        .onChange(of: model.pendingGpx == nil) { _, none in if !none { mode = 1; showVideo = true } }
        .onAppear { if model.pendingGpx != nil { mode = 1; showVideo = true } }
    }

    private func seg(_ t: String, _ i: Int) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { mode = i } } label: {
            Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(mode == i ? Theme.text : Theme.text3)
                .frame(maxWidth: .infinity).frame(height: 34).background(mode == i ? Theme.card2 : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Görsel
    @ViewBuilder private var imageMode: some View {
        Text("Bir aktivite seç; fotoğrafına rotayı ve değerleri ekle, şablon ve rengi ayarla, paylaş.")
            .font(.subheadline).foregroundStyle(Theme.text2)
        if act.activities.isEmpty {
            Panel {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30)).foregroundStyle(Theme.text3)
                    Text("Henüz aktivite yok").font(.headline).foregroundStyle(Theme.text)
                    Text("Özet sekmesinden bir kayıt başlat; bitince burada görünür.").font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
            }
        } else {
            ForEach(act.activities) { a in
                Button { editing = a } label: { row(a) }.buttonStyle(.plain)
            }
        }
    }

    private func row(_ a: Activity) -> some View {
        HStack(spacing: 12) {
            RouteThumb(act: act, a: a).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(a.type.title(a.start)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(a.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.text2)
                Text("\(Fmt.km(a.distance)) km · \(Fmt.dur(a.moving))").font(.caption.weight(.semibold)).foregroundStyle(Theme.cDist).monospacedDigit()
            }
            Spacer()
            Image(systemName: "photo.badge.plus").foregroundStyle(a.type.color)
        }
        .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Video
    @ViewBuilder private var videoMode: some View {
        Text("Videona iki şekilde ekleme yapabilirsin: canlı veri göstergeleri (hız, rota, eğim) ya da istediğin saniyede belirip kaybolan sabit aktivite kartı. Video cihazından çıkmaz.")
            .font(.subheadline).foregroundStyle(Theme.text2)
        Button { showVideo = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "film.stack.fill").font(.system(size: 30)).foregroundStyle(Theme.onAcc)
                Text("Video seç").font(.headline).foregroundStyle(Theme.onAcc)
                Text("GoPro ise sensör verisi videodan okunur").font(.caption).foregroundStyle(Theme.onAcc.opacity(0.75))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            .background(Theme.acc, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }.buttonStyle(.plain)
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nasıl çalışır").font(.headline).foregroundStyle(Theme.text)
                step("1", "Canlı göstergeler", "GoPro sensör verisi ya da GPS kaydıyla hız, rota ve eğim video boyunca akar.")
                step("2", "Aktivite kartı", "Fotoğraftaki gibi rota ve değerler; hangi saniyede başlayacağını ve ne kadar kalacağını sen seçersin.")
                step("3", "Videoyu seç", "Sıkıştırılmamış orijinal dosya en iyi sonucu verir. İkisini birlikte de kullanabilirsin.")
            }
        }
        Button { showCam = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent").font(.title3).foregroundStyle(ActType.motor.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GoPro ile sürüş kaydı").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Kamerayı bağla, GPS ile birlikte başlat").font(.caption).foregroundStyle(Theme.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.text3)
            }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func step(_ n: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.caption.weight(.bold)).foregroundStyle(Theme.acc).frame(width: 22, height: 22).background(Theme.acc.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(d).font(.caption).foregroundStyle(Theme.text2)
            }
        }
    }
}
