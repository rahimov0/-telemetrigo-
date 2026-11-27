import SwiftUI
import KrovaCore

/// Stüdyo: bir aktiviteden ya da bir videodan başla. Fotoğraf, video kartı ve canlı veri tek yerden.
struct StudioTab: View {
    @AppStorage("units") private var unitsPref = "metric"   // birim değişince ekran yenilensin
    @AppStorage("lang") private var langPref = "auto"
    @EnvironmentObject var model: AppModel
    @ObservedObject var act: ActivityRecorder
    @State private var picked: Activity?          // seçenek sayfası
    @State private var editing: Activity?         // fotoğraf editörü
    @State private var showCam = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(L("Stüdyo")).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(L("Videodan başla"))
                    Button { model.openVideo(mode: "live", lead: nil) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "film.stack.fill").font(.system(size: 22)).foregroundStyle(Theme.onAcc)
                                .frame(width: 52, height: 52).background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L("Video seç")).font(.headline).foregroundStyle(Theme.onAcc)
                                Text(L("GoPro sensör verisi ya da GPS ile canlı göstergeler")).font(.caption).foregroundStyle(Theme.onAcc.opacity(0.75))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.onAcc.opacity(0.6))
                        }
                        .padding(16).background(Theme.acc, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }.buttonStyle(.plain)
                    Button { showCam = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gauge.with.dots.needle.67percent").font(.title3).foregroundStyle(ActType.motor.color).frame(width: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("GoPro ile sürüş kaydı")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text(L("Kamerayı bağla, GPS ile birlikte başlat")).font(.caption).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.text3)
                        }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }.buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(L("Aktiviteden başla"))
                    Text(L("Bir aktiviteye dokun: fotoğrafa ya da videoya ekle.")).font(.subheadline).foregroundStyle(Theme.text2)
                    if act.activities.isEmpty {
                        Panel {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30)).foregroundStyle(Theme.text3)
                                Text(L("Henüz aktivite yok")).font(.headline).foregroundStyle(Theme.text)
                                Text(L("Özet sekmesinden bir kayıt başlat; bitince burada görünür.")).font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                    } else {
                        ForEach(act.activities.prefix(30)) { a in
                            Button { picked = a } label: { row(a) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 130)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $picked) { a in
            SourceSheet(a: a) { choice in
                picked = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    switch choice {
                    case .photo: editing = a
                    case .card: model.openVideo(mode: "card", lead: a)
                    case .live: model.openVideo(mode: "live", lead: a)
                    }
                }
            }
            .presentationDetents([.height(330), .medium]).presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { a in
            PhotoEditorSheet(gpx: act.gpxText(a), name: a.type.title(a.start), type: a.type.rawValue, steps: nil, kcal: Cal.active(a), lead: a)
                .environmentObject(model)
        }
        .sheet(isPresented: $showCam) { RecordView().environmentObject(model) }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.text3).tracking(1.2)
    }

    private func row(_ a: Activity) -> some View {
        HStack(spacing: 12) {
            RouteThumb(act: act, a: a).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(a.type.title(a.start)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(a.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.text2)
                Text("\(Fmt.km(a.distance)) \(Units.distUnit) · \(Fmt.dur(a.moving))").font(.caption.weight(.semibold)).foregroundStyle(Theme.cDist).monospacedDigit()
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.text3)
        }
        .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

enum SourceChoice { case photo, card, live }

/// "Bu aktiviteyle ne yapalım?" iki adımlı seçim: Fotoğraf / Video → Kart / Canlı veri
struct SourceSheet: View {
    @AppStorage("lang") private var langPref = "auto"   // dil değişince bu ekran da yeniden çizilsin
    let a: Activity
    var videoOnly = false
    let pick: (SourceChoice) -> Void
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if step == 1 && !videoOnly {
                    Button { withAnimation(.easeOut(duration: 0.15)) { step = 0 } } label: { Image(systemName: "chevron.left").font(.body.weight(.semibold)) }
                        .foregroundStyle(Theme.text2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(step == 0 ? "Ne ekleyelim?" : L("Videoya nasıl eklensin?")).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Text(a.type.title(a.start)).font(.subheadline).foregroundStyle(Theme.text2)
                }
                Spacer()
            }.padding(.top, 22)
            if step == 0 {
                option("photo.on.rectangle.angled", L("Fotoğrafa ekle"), L("Rota ve değerlerle paylaşılabilir görsel"), Theme.acc) { pick(.photo) }
                option("film.stack.fill", L("Videoya ekle"), L("Kart ya da canlı veri"), ActType.motor.color) { withAnimation(.easeOut(duration: 0.15)) { step = 1 } }
            } else {
                option("rectangle.on.rectangle.angled", L("Aktivite kartı"), L("Rota ve değerler sabit kart olarak belirir; hangi saniyede ve ne kadar süre kalacağını sen seçersin"), Theme.acc) { pick(.card) }
                option("speedometer", L("Canlı veri"), L("Hız, rota ve eğim göstergeleri videoyla birlikte akar"), ActType.motor.color) { pick(.live) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).background(Theme.bg.ignoresSafeArea())
        .onAppear { if videoOnly { step = 1 } }
    }

    private func option(_ icon: String, _ title: String, _ sub: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 48, height: 48).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Theme.text)
                    Text(sub).font(.caption).foregroundStyle(Theme.text2).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.text3)
            }
            .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(.plain)
    }
}


/// Video editörü sayfası (Stüdyo ve Özet'ten aynı yerden açılır)
struct VideoRoute: Identifiable { let id = UUID(); var mode: String; var lead: Activity? }

struct VideoCover: View {
    @AppStorage("lang") private var langPref = "auto"   // dil değişince bu ekran da yeniden çizilsin
    @EnvironmentObject var model: AppModel
    let v: VideoRoute
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.videoRoute = nil } label: {
                    Text(L("Kapat")).font(.body.weight(.medium)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 34)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text(v.mode == "card" ? L("Aktivite kartı") : L("Canlı veri")).font(.headline).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 66, height: 1)
            }.padding(.horizontal, 16).padding(.vertical, 8)
            VideoTab(mode: v.mode, lead: v.lead).environmentObject(model)
        }.background(Color.black.ignoresSafeArea())
    }
}
