import Foundation
import CoreLocation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var query = ""
    @Published var nearby: LoadingState<[NearbyStop]> = .idle

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    var matchingLines: [BusLine] {
        Array(container.search.lines(container.lines, matching: query).prefix(5))
    }

    var matchingStops: [BusStop] {
        Array(container.search.stops(container.stops, matching: query).prefix(5))
    }

    var favoriteLines: [BusLine] {
        container.lines.filter { container.favorites.lineIDs.contains($0.number) }
    }

    var favoriteStops: [BusStop] {
        container.stops.filter { container.favorites.stopIDs.contains($0.stopID) }
    }

    func loadNearbyPreview() async {
        guard let location = container.location.currentLocation else { return }
        nearby = .loading
        do {
            let result = try await container.transportService.fetchNearbyStops(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, cachedStops: container.stops)
            nearby = .loaded(Array(result.value.prefix(5)), isFromCache: result.isFromCache, updatedAt: result.fetchedAt)
        } catch {
            nearby = .failed("Yakındaki duraklar alınamadı.")
        }
    }
}

@MainActor
final class LineSearchViewModel: ObservableObject {
    @Published var query = ""
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    var results: [BusLine] {
        container.search.lines(container.lines, matching: query)
    }
}

@MainActor
final class StopSearchViewModel: ObservableObject {
    @Published var query = ""
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    var results: [BusStop] {
        container.search.stops(container.stops, matching: query)
    }
}

@MainActor
final class LineDetailViewModel: ObservableObject {
    @Published var direction: Direction = .outbound
    @Published var selectedServiceTypeID: String = "1"
    @Published var vehicles: LoadingState<[VehicleLocation]> = .idle

    let line: BusLine
    private let container: AppContainer

    init(line: BusLine, container: AppContainer) {
        self.line = line
        self.container = container
    }

    var serviceTypes: [(id: String, label: String)] {
        let ids = Set(container.timetable.filter { $0.lineNumber == line.number }.map(\.serviceTypeID))
        return ids.sorted().map { ($0, container.configuration.serviceTypeLabel(for: $0)) }
    }

    var upcomingDepartures: [TimetableEntry] {
        let now = Self.timeFormatter.string(from: Date())
        let entries = container.timetable
            .filter { $0.lineNumber == line.number && $0.direction == direction && $0.serviceTypeID == selectedServiceTypeID }
            .sorted { $0.departureTime < $1.departureTime }
        let upcoming = entries.filter { $0.departureTime >= now }
        return Array((upcoming.isEmpty ? entries : upcoming).prefix(20))
    }

    var routeStops: [BusStop] {
        container.stops.filter { $0.servingLineNumbers.contains(line.number) }
    }

    var routePoints: [RoutePoint] {
        container.routePoints
            .filter { $0.lineNumber == line.number && $0.direction == direction }
            .sorted { $0.sequence < $1.sequence }
    }

    func loadVehicles() async {
        vehicles = .loading
        do {
            let result = try await container.transportService.fetchLineVehicleLocations(lineID: line.number)
            vehicles = result.value.isEmpty ? .empty("Bu hatta şu anda canlı araç konumu yok.") : .loaded(result.value, isFromCache: result.isFromCache, updatedAt: result.fetchedAt)
        } catch {
            vehicles = .failed("Canlı araç konumları alınamadı.")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter
    }()
}

@MainActor
final class StopDetailViewModel: ObservableObject {
    @Published var arrivals: LoadingState<[StopArrival]> = .idle
    let stop: BusStop
    private let container: AppContainer

    init(stop: BusStop, container: AppContainer) {
        self.stop = stop
        self.container = container
    }

    var servingLines: [BusLine] {
        container.lines.filter { stop.servingLineNumbers.contains($0.number) }
    }

    func loadArrivals() async {
        arrivals = .loading
        do {
            let result = try await container.transportService.fetchApproachingBuses(stopID: stop.stopID)
            arrivals = result.value.isEmpty ? .empty("Bu durağa yaklaşan canlı otobüs bulunamadı. Tarife bilgilerini kontrol edin.") : .loaded(result.value, isFromCache: result.isFromCache, updatedAt: result.fetchedAt)
        } catch {
            arrivals = .failed("Canlı yaklaşan otobüs bilgisi alınamadı. Tarife bilgileri kullanılabilir.")
        }
    }
}

@MainActor
final class NearbyStopsViewModel: ObservableObject {
    @Published var state: LoadingState<[NearbyStop]> = .idle
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func load() async {
        guard let location = container.location.currentLocation else {
            state = .empty("Yakındaki durakları görmek için konum izni verin.")
            return
        }
        state = .loading
        do {
            let result = try await container.transportService.fetchNearbyStops(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, cachedStops: container.stops)
            state = result.value.isEmpty ? .empty("Yakınlarda durak bulunamadı.") : .loaded(result.value, isFromCache: result.isFromCache, updatedAt: result.fetchedAt)
        } catch {
            state = .failed("Yakındaki duraklar alınamadı.")
        }
    }
}

extension Date {
    var shortUpdatedText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: self)
    }
}
