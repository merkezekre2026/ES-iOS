import Foundation
import CoreLocation

protocol TransportDataServiceProtocol {
    func fetchLines(forceRefresh: Bool) async throws -> CachedValue<[BusLine]>
    func fetchStops(forceRefresh: Bool) async throws -> CachedValue<[BusStop]>
    func fetchTimetable(forceRefresh: Bool) async throws -> CachedValue<[TimetableEntry]>
    func fetchRouteGeometry(forceRefresh: Bool) async throws -> CachedValue<[RoutePoint]>
    func fetchApproachingBuses(stopID: String) async throws -> CachedValue<[StopArrival]>
    func fetchLineVehicleLocations(lineID: String) async throws -> CachedValue<[VehicleLocation]>
    func fetchNearbyStops(latitude: Double, longitude: Double, cachedStops: [BusStop]) async throws -> CachedValue<[NearbyStop]>
}

final class TransportDataService: TransportDataServiceProtocol {
    private let configuration: EndpointConfiguration
    private let session: URLSession
    private let cache: FileCacheStore
    private let parser = CSVParser()
    private let decoder = JSONDecoder()

    init(configuration: EndpointConfiguration, session: URLSession = .shared, cache: FileCacheStore = FileCacheStore()) {
        self.configuration = configuration
        self.session = session
        self.cache = cache
    }

    func fetchLines(forceRefresh: Bool = false) async throws -> CachedValue<[BusLine]> {
        try await fetchCSV(key: "lines", url: configuration.linesCSVURL, forceRefresh: forceRefresh) {
            TransitMapper(configuration: configuration).lines(from: $0)
        }
    }

    func fetchStops(forceRefresh: Bool = false) async throws -> CachedValue<[BusStop]> {
        try await fetchCSV(key: "stops", url: configuration.stopsCSVURL, forceRefresh: forceRefresh) {
            TransitMapper(configuration: configuration).stops(from: $0)
        }
    }

    func fetchTimetable(forceRefresh: Bool = false) async throws -> CachedValue<[TimetableEntry]> {
        try await fetchCSV(key: "timetable", url: configuration.timetableCSVURL, forceRefresh: forceRefresh) {
            TransitMapper(configuration: configuration).timetable(from: $0)
        }
    }

    func fetchRouteGeometry(forceRefresh: Bool = false) async throws -> CachedValue<[RoutePoint]> {
        try await fetchCSV(key: "routes", url: configuration.routeGeometryCSVURL, forceRefresh: forceRefresh) {
            TransitMapper(configuration: configuration).routePoints(from: $0)
        }
    }

    func fetchApproachingBuses(stopID: String) async throws -> CachedValue<[StopArrival]> {
        let url = try configuration.approachingBusesURL(stopID: stopID)
        let data = try await networkData(from: url)
        let rows = try decoder.decode([ApproachingBusDTO].self, from: data)
        let timestamp = Date()
        let arrivals = rows.map { $0.arrival(stopID: stopID, timestamp: timestamp) }
        return CachedValue(value: arrivals, fetchedAt: timestamp, isFromCache: false)
    }

    func fetchLineVehicleLocations(lineID: String) async throws -> CachedValue<[VehicleLocation]> {
        let url = try configuration.lineVehiclesURL(lineID: lineID)
        let data = try await networkData(from: url)
        let response = try decoder.decode(LineVehicleResponseDTO.self, from: data)
        let timestamp = Date()
        let vehicles = response.HatOtobusKonumlari.map { $0.vehicle(lineID: lineID, timestamp: timestamp) }
        return CachedValue(value: vehicles, fetchedAt: timestamp, isFromCache: false)
    }

    func fetchNearbyStops(latitude: Double, longitude: Double, cachedStops: [BusStop]) async throws -> CachedValue<[NearbyStop]> {
        do {
            let url = try configuration.nearbyStopsURL(latitude: latitude, longitude: longitude)
            let data = try await networkData(from: url)
            let rows = try decoder.decode([NearbyStopDTO].self, from: data)
            let stops = rows.map { dto in
                NearbyStop(
                    stop: BusStop(stopID: dto.durakId, name: dto.adi, latitude: dto.enlem, longitude: dto.boylam, servingLineNumbers: cachedStops.first(where: { $0.stopID == dto.durakId })?.servingLineNumbers ?? []),
                    distanceMeters: dto.mesafe
                )
            }
            return CachedValue(value: stops, fetchedAt: Date(), isFromCache: false)
        } catch {
            let origin = CLLocation(latitude: latitude, longitude: longitude)
            let fallback = cachedStops
                .map { stop in
                    NearbyStop(stop: stop, distanceMeters: origin.distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude)))
                }
                .sorted { $0.distanceMeters < $1.distanceMeters }
                .prefix(20)
            return CachedValue(value: Array(fallback), fetchedAt: Date(), isFromCache: true)
        }
    }

    private func fetchCSV<Value>(key: String, url: URL, forceRefresh: Bool, transform: (CSVDocument) -> Value) async throws -> CachedValue<Value> {
        do {
            let data = try await networkData(from: url)
            try cache.save(data: data, for: key)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return CachedValue(value: transform(parser.parse(text)), fetchedAt: Date(), isFromCache: false)
        } catch {
            if let cached = try? cache.loadData(for: key), let text = String(data: cached.0, encoding: .utf8) {
                return CachedValue(value: transform(parser.parse(text)), fetchedAt: cached.1, isFromCache: true)
            }
            throw error
        }
    }

    private func networkData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct ApproachingBusDTO: Decodable {
    let KalanDurakSayisi: Int?
    let HattinYonu: Int?
    let KoorY: FlexibleDouble?
    let BisikletAparatliMi: Bool?
    let KoorX: FlexibleDouble?
    let EngelliMi: Bool?
    let HatNumarasi: Int?
    let HatAdi: String?
    let OtobusId: Int?

    func arrival(stopID: String, timestamp: Date) -> StopArrival {
        StopArrival(
            stopID: stopID,
            lineNumber: HatNumarasi.map(String.init) ?? "",
            lineName: HatAdi ?? "",
            busID: OtobusId.map(String.init) ?? UUID().uuidString,
            direction: HattinYonu == 2 ? .inbound : .outbound,
            remainingStopCount: KalanDurakSayisi,
            latitude: KoorX?.value,
            longitude: KoorY?.value,
            wheelchairAccessible: EngelliMi ?? false,
            bicycleSupported: BisikletAparatliMi ?? false,
            timestamp: timestamp,
            source: .realtime
        )
    }
}

struct LineVehicleResponseDTO: Decodable {
    let HataMesaj: String?
    let HatOtobusKonumlari: [LineVehicleDTO]
    let HataVarMi: Bool?
}

struct LineVehicleDTO: Decodable {
    let Yon: Int?
    let KoorX: FlexibleDouble
    let KoorY: FlexibleDouble
    let OtobusId: Int

    func vehicle(lineID: String, timestamp: Date) -> VehicleLocation {
        VehicleLocation(busID: String(OtobusId), lineNumber: lineID, direction: Yon == 2 ? .inbound : .outbound, latitude: KoorX.value, longitude: KoorY.value, timestamp: timestamp)
    }
}

struct NearbyStopDTO: Decodable {
    let durakId: String
    let enlem: Double
    let adi: String
    let mesafe: Double
    let boylam: Double
}

struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self), let double = Double.normalized(string) {
            value = double
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Double veya virgüllü ondalık bekleniyordu.")
        }
    }
}

struct SearchEngine {
    func lines(_ lines: [BusLine], matching query: String) -> [BusLine] {
        let q = query.normalizedForSearch().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return lines }
        let scoredLines: [(line: BusLine, score: Int)] = lines.compactMap { line in
            let number = line.number.normalizedForSearch()
            let text = "\(line.title) \(line.routeSummary) \(line.start) \(line.end)".normalizedForSearch()
            let score: Int?
            if number == q { score = 0 }
            else if number.hasPrefix(q) { score = 1 }
            else if number.contains(q) { score = 2 }
            else if text.contains(q) { score = 3 }
            else { score = nil }
            guard let score else { return nil }
            return (line: line, score: score)
        }

        return scoredLines
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.line.number.localizedStandardCompare(rhs.line.number) == .orderedAscending
                }
                return lhs.score < rhs.score
            }
            .map(\.line)
    }

    func stops(_ stops: [BusStop], matching query: String) -> [BusStop] {
        let q = query.normalizedForSearch().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return stops }
        let scoredStops: [(stop: BusStop, score: Int)] = stops.compactMap { stop in
            let id = stop.stopID.normalizedForSearch()
            let name = stop.name.normalizedForSearch()
            let score: Int?
            if id == q { score = 0 }
            else if id.contains(q) { score = 1 }
            else if name.contains(q) { score = 2 }
            else {
                let distance = levenshtein(q, name)
                score = distance <= max(2, q.count / 3) ? 3 + distance : nil
            }
            guard let score else { return nil }
            return (stop: stop, score: score)
        }

        return scoredStops
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.stop.name.localizedStandardCompare(rhs.stop.name) == .orderedAscending
                }
                return lhs.score < rhs.score
            }
            .map(\.stop)
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                matrix[i][j] = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
        }
        return matrix[a.count][b.count]
    }
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
