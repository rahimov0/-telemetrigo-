import Foundation
import HealthKit
import CoreLocation

extension ActType {
    var hkType: HKWorkoutActivityType {
        switch self {
        case .yuruyus: return .walking
        case .kosu: return .running
        case .bisiklet: return .cycling
        case .motor: return .other
        }
    }
}

/// Apple Sağlık: günlük adımlar, bitirilen aktiviteyi antrenman + rota olarak kaydetme
final class HealthManager: ObservableObject {
    private let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Kullanıcı bağlanmayı seçti mi (okuma izni sistemden sorgulanamaz, bu yüzden kendimiz tutuyoruz)
    @Published var connected = UserDefaults.standard.bool(forKey: "healthOn")
    @Published var stepsToday: Int = 0
    @Published var distToday: Double = 0
    @Published var week: [(day: Date, steps: Int)] = []
    @Published var lastError: String?

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var walkDist: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    private var cycDist: HKQuantityType { HKQuantityType(.distanceCycling) }

    func connect() {
        guard Self.available else { lastError = "Bu cihazda Sağlık verisi yok."; return }
        let read: Set<HKObjectType> = [stepType, walkDist]
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), walkDist, cycDist]
        store.requestAuthorization(toShare: share, read: read) { [weak self] ok, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let err { self.lastError = err.localizedDescription; return }
                self.connected = ok
                UserDefaults.standard.set(ok, forKey: "healthOn")
                if ok { self.refresh() }
            }
        }
    }

    func disconnect() { connected = false; UserDefaults.standard.set(false, forKey: "healthOn"); stepsToday = 0; week = [] }

    /// Bugünkü ve son 7 günün adımları
    func refresh() {
        guard connected, Self.available else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let from = cal.date(byAdding: .day, value: -6, to: today) else { return }
        let pred = HKQuery.predicateForSamples(withStart: from, end: nil, options: .strictStartDate)
        let q = HKStatisticsCollectionQuery(quantityType: stepType, quantitySamplePredicate: pred, options: .cumulativeSum,
                                            anchorDate: today, intervalComponents: DateComponents(day: 1))
        q.initialResultsHandler = { [weak self] _, res, _ in
            guard let res else { return }
            var days: [(day: Date, steps: Int)] = []
            res.enumerateStatistics(from: from, to: Date()) { s, _ in
                days.append((s.startDate, Int(s.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
            }
            DispatchQueue.main.async { self?.week = days; self?.stepsToday = days.last?.steps ?? 0 }
        }
        store.execute(q)
        let dq = HKStatisticsQuery(quantityType: walkDist, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: today, end: nil, options: .strictStartDate), options: .cumulativeSum) { [weak self] _, s, _ in
            let m = s?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            DispatchQueue.main.async { self?.distToday = m }
        }
        store.execute(dq)
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
        guard connected, Self.available, let end = a.end else { return }
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = a.type.hkType
        cfg.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: cfg, device: .local())
        builder.beginCollection(withStart: a.start) { [weak self] ok, _ in
            guard let self, ok else { return }
            var samples: [HKSample] = []
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
