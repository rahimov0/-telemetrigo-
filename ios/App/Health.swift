import Foundation
import HealthKit
import KrovaCore
import CoreLocation

extension ActType {
    var hkType: HKWorkoutActivityType {
        switch self {
        case .yuruyus: return .walking
        case .kosu: return .running
        case .bisiklet: return .cycling
        case .tirmanis: return .hiking
        case .motor, .arac: return .other
        }
    }
}

/// Apple Sağlık: günlük adımlar, bitirilen aktiviteyi antrenman + rota olarak kaydetme
final class HealthManager: ObservableObject {
    private let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Kullanıcı bağlanmayı seçti mi (okuma izni sistemden sorgulanamaz, bu yüzden kendimiz tutuyoruz)
    @Published var connected = UserDefaults.standard.bool(forKey: "healthOn")
    @Published var write = UserDefaults.standard.object(forKey: "healthWrite") as? Bool ?? true { didSet { UserDefaults.standard.set(write, forKey: "healthWrite") } }
    /// Kaloriyi Sağlık'a yazmayı kapatmak: saat zaten ölçüyorsa çift sayılmasın
    @Published var writeEnergy = UserDefaults.standard.object(forKey: "healthWriteEnergy") as? Bool ?? true { didSet { UserDefaults.standard.set(writeEnergy, forKey: "healthWriteEnergy") } }
    @Published var stepsToday: Int = 0
    @Published var distToday: Double = 0
    @Published var week: [(day: Date, steps: Int)] = []
    @Published var lastError: String?

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var walkDist: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    private var cycDist: HKQuantityType { HKQuantityType(.distanceCycling) }
    private var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var massType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var heightType: HKQuantityType { HKQuantityType(.height) }

    /// İzinleri (yeni türler dahil) yeniden ister, sonra kilo/boyu okur
    func fetchProfile(_ done: @escaping (Double?, Double?, String?) -> Void) {
        let read: Set<HKObjectType> = [stepType, walkDist, energyType, HKObjectType.activitySummaryType(), massType, heightType]
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), walkDist, cycDist, energyType]
        store.requestAuthorization(toShare: share, read: read) { [weak self] _, err in
            guard let self else { return }
            if let err { DispatchQueue.main.async { done(nil, nil, err.localizedDescription) }; return }
            self.loadProfile { w, h in
                if w == nil && h == nil { done(nil, nil, "Sağlık'ta kilo/boy bulunamadı ya da erişim kapalı. iPhone Ayarlar > Sağlık > Veri Erişimi > KROVA'dan aç; ya da elle gir.") }
                else { done(w, h, "Sağlık'tan alındı.") }
            }
        }
    }

    /// Sağlık'taki en son kilo ve boy
    func loadProfile(_ done: @escaping (Double?, Double?) -> Void) {
        func latest(_ t: HKQuantityType, _ unit: HKUnit, _ cb: @escaping (Double?) -> Void) {
            let q = HKSampleQuery(sampleType: t, predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, r, _ in
                cb((r?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
        latest(massType, .gramUnit(with: .kilo)) { w in
            latest(self.heightType, .meterUnit(with: .centi)) { h in
                DispatchQueue.main.async { done(w.map { ($0 * 10).rounded() / 10 }, h.map { $0.rounded() }) }
            }
        }
    }

    func connect() {
        guard Self.available else { lastError = "Bu cihazda Sağlık verisi yok."; return }
        let read: Set<HKObjectType> = [stepType, walkDist, energyType, HKObjectType.activitySummaryType(), massType, heightType]
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), walkDist, cycDist, energyType]
        store.requestAuthorization(toShare: share, read: read) { [weak self] ok, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let err { self.lastError = err.localizedDescription; return }
                self.connected = ok
                UserDefaults.standard.set(ok, forKey: "healthOn")
                if ok { self.refresh(); self.startLive() }
            }
        }
    }

    func disconnect() { observers.forEach { store.stop($0) }; observers = []; connected = false; UserDefaults.standard.set(false, forKey: "healthOn"); stepsToday = 0; week = [] }

    /// Seçili günün haftası (Pzt–Paz): günlük adım ve yürüme mesafesi
    @Published var weekDist: [Date: Double] = [:]
    /// Sağlık'taki günlük aktif enerji (kcal): Apple Watch, iPhone ve bu uygulamanın yazdıkları dahil, Hareket halkasıyla aynı
    @Published var weekEnergy: [Date: Double] = [:]
    @Published var weekMove: [Date: Double] = [:]   // Hareket halkası (HKActivitySummary)
    private var loadedWeek: Date?
    /// Sağlık'a yeni adım/enerji/kat verisi düştüğünde artar; ekranlar bunu izleyip kendini yeniler
    @Published var tick = 0
    private var observers: [HKObserverQuery] = []
    private var lastTick = Date.distantPast
    /// Uygulama açıkken Sağlık'taki değişiklikleri canlı izler (Fitness gibi anında güncellenir)
    func startLive() {
        guard connected, Self.available, observers.isEmpty else { return }
        for t in [stepType, energyType] {
            let q = HKObserverQuery(sampleType: t, predicate: nil) { [weak self] _, done, _ in
                DispatchQueue.main.async {
                    // Yürürken sürekli tetiklenir: en fazla 3 sn'de bir yenile
                    guard let self, Date().timeIntervalSince(self.lastTick) > 3 else { return }
                    self.lastTick = Date(); self.tick += 1
                }
                done()
            }
            store.execute(q); observers.append(q)
        }
    }
    func refresh() {
        // Kalori okuma izni sonradan eklendi: bağlı olanlara bir kez sorulur
        if connected, !UserDefaults.standard.bool(forKey: "healthEnergyAsked3") {
            let read: Set<HKObjectType> = [stepType, walkDist, energyType, HKObjectType.activitySummaryType(), massType, heightType]
            let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), walkDist, cycDist, energyType]
            store.requestAuthorization(toShare: share, read: read) { [weak self] ok, _ in
                DispatchQueue.main.async { if ok { UserDefaults.standard.set(true, forKey: "healthEnergyAsked3") }; self?.loadWeek(containing: Date(), force: true) }
            }
        }
        startLive()
        loadWeek(containing: Date(), force: true)
    }

    func loadWeek(containing day: Date, force: Bool = false) {
        guard connected, Self.available else { return }
        var cal = Calendar(identifier: .iso8601); cal.locale = Locale(identifier: "tr_TR")
        guard let from = cal.dateInterval(of: .weekOfYear, for: day)?.start, let to = cal.date(byAdding: .day, value: 7, to: from) else { return }
        if !force, loadedWeek == from { return }
        loadedWeek = from
        let range = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let q = HKStatisticsCollectionQuery(quantityType: stepType, quantitySamplePredicate: range, options: .cumulativeSum,
                                            anchorDate: from, intervalComponents: DateComponents(day: 1))
        q.initialResultsHandler = { [weak self] _, res, _ in
            var days: [(day: Date, steps: Int)] = []
            res?.enumerateStatistics(from: from, to: to) { s, _ in
                days.append((s.startDate, Int(s.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
            }
            DispatchQueue.main.async { self?.week = days; self?.stepsToday = days.first(where: { Calendar.current.isDateInToday($0.day) })?.steps ?? 0 }
        }
        store.execute(q)
        // Bu uygulamanın antrenman olarak yazdığı mesafe sayılmaz; yoksa az adımla çok km görünür
        let own = NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        let dp = NSCompoundPredicate(andPredicateWithSubpredicates: [range, own])
        let dq = HKStatisticsCollectionQuery(quantityType: walkDist, quantitySamplePredicate: dp, options: .cumulativeSum,
                                             anchorDate: from, intervalComponents: DateComponents(day: 1))
        dq.initialResultsHandler = { [weak self] _, res, _ in
            var m: [Date: Double] = [:]
            res?.enumerateStatistics(from: from, to: to) { s, _ in m[Calendar.current.startOfDay(for: s.startDate)] = s.sumQuantity()?.doubleValue(for: .meter()) ?? 0 }
            DispatchQueue.main.async { self?.weekDist = m }
        }
        store.execute(dq)
        let eq = HKStatisticsCollectionQuery(quantityType: energyType, quantitySamplePredicate: range, options: .cumulativeSum,
                                             anchorDate: from, intervalComponents: DateComponents(day: 1))
        eq.initialResultsHandler = { [weak self] _, res, _ in
            var m: [Date: Double] = [:]
            res?.enumerateStatistics(from: from, to: to) { s, _ in m[Calendar.current.startOfDay(for: s.startDate)] = s.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0 }
            DispatchQueue.main.async { self?.weekEnergy.merge(m) { _, new in new } }
        }
        store.execute(eq)
        // Fitness'taki Hareket halkasının kendisi: Watch/iPhone kaynaklarını Apple'ın kendi yöntemiyle birleştirir
        let c = Calendar.current
        for i in 0..<7 {
            guard let d = c.date(byAdding: .day, value: i, to: from) else { continue }
            var dc = c.dateComponents([.era, .year, .month, .day], from: d); dc.calendar = c
            let sq = HKActivitySummaryQuery(predicate: HKQuery.predicateForActivitySummary(with: dc)) { [weak self] _, sums, _ in
                guard let x = sums?.first else { return }
                let v = x.activeEnergyBurned.doubleValue(for: .kilocalorie()), key = c.startOfDay(for: d)
                DispatchQueue.main.async { self?.weekMove[key] = v }
            }
            store.execute(sq)
        }
    }

    /// Bir aktivitenin süresindeki adım sayısı (yürüyüş ve koşu için)
    func steps(from: Date, to: Date, _ done: @escaping (Int?) -> Void) {
        guard connected, Self.available else { done(nil); return }
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: pred, options: .cumulativeSum) { _, s, _ in
            let v = s?.sumQuantity()?.doubleValue(for: .count())
            DispatchQueue.main.async { done(v.map { Int($0) }) }
        }
        store.execute(q)
    }

    /// Bitmiş aktiviteyi Sağlık'a antrenman ve rota olarak yaz
    func save(_ a: Activity, points: [TrackPoint]) {
        guard connected, write, Self.available, a.type.kind.writesToHealth, let end = a.end else { return }
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = a.type.hkType
        cfg.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: cfg, device: .local())
        builder.beginCollection(withStart: a.start) { [weak self] ok, _ in
            guard let self, ok else { return }
            var samples: [HKSample] = []
            if writeEnergy, let kc = Cal.active(a), kc > 1 {
                samples.append(HKQuantitySample(type: self.energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kc), start: a.start, end: end))
            }
            if a.distance > 10 {
                let t = a.type == .bisiklet ? self.cycDist : self.walkDist
                samples.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: .meter(), doubleValue: a.distance), start: a.start, end: end))
            }
            let finish = {
                builder.endCollection(withEnd: end) { ok, _ in
                    guard ok else { return }
                    builder.finishWorkout { workout, _ in
                        guard let workout else { return }
                        self.saveRoute(points, to: workout)
                    }
                }
            }
            if samples.isEmpty { finish() } else { builder.add(samples) { _, _ in finish() } }
        }
    }

    private func saveRoute(_ pts: [TrackPoint], to workout: HKWorkout) {
        let locs: [CLLocation] = pts.filter { $0.ha <= 50 }.map {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.la, longitude: $0.lo), altitude: $0.al ?? 0,
                       horizontalAccuracy: $0.ha, verticalAccuracy: $0.al == nil ? -1 : 10, course: -1, speed: $0.sp ?? -1,
                       timestamp: Date(timeIntervalSince1970: $0.t))
        }
        guard locs.count > 1 else { return }
        let rb = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        rb.insertRouteData(locs) { ok, _ in
            guard ok else { return }
            rb.finishRoute(with: workout, metadata: nil) { _, _ in }
        }
    }
}
