import SwiftUI

@main
struct ES_iOSApp: App {
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(container)
                .environmentObject(container.favorites)
                .environmentObject(container.recents)
                .environmentObject(container.location)
        }
    }
}

final class AppContainer: ObservableObject {
    let configuration: EndpointConfiguration
    let transportService: TransportDataServiceProtocol
    let cache: FileCacheStore
    let favorites: FavoritesStore
    let recents: RecentSearchStore
    let location: LocationService
    let search = SearchEngine()

    @Published var lines: [BusLine] = []
    @Published var stops: [BusStop] = []
    @Published var timetable: [TimetableEntry] = []
    @Published var routePoints: [RoutePoint] = []
    @Published var isFromCache = false
    @Published var lastUpdated: Date?
    @Published var loadError: String?
    @Published var isLoading = false

    init(configuration: EndpointConfiguration, transportService: TransportDataServiceProtocol, cache: FileCacheStore, favorites: FavoritesStore, recents: RecentSearchStore, location: LocationService) {
        self.configuration = configuration
        self.transportService = transportService
        self.cache = cache
        self.favorites = favorites
        self.recents = recents
        self.location = location
    }

    static func live() -> AppContainer {
        let config = EndpointConfiguration.load()
        let cache = FileCacheStore()
        return AppContainer(
            configuration: config,
            transportService: TransportDataService(configuration: config, cache: cache),
            cache: cache,
            favorites: FavoritesStore(),
            recents: RecentSearchStore(),
            location: LocationService()
        )
    }

    @MainActor
    func bootstrap(forceRefresh: Bool = false) async {
        if isLoading { return }
        isLoading = true
        loadError = nil
        do {
            async let linesResult = transportService.fetchLines(forceRefresh: forceRefresh)
            async let stopsResult = transportService.fetchStops(forceRefresh: forceRefresh)
            async let timetableResult = transportService.fetchTimetable(forceRefresh: forceRefresh)
            async let routesResult = transportService.fetchRouteGeometry(forceRefresh: forceRefresh)
            let loaded = try await (linesResult, stopsResult, timetableResult, routesResult)
            lines = loaded.0.value
            stops = loaded.1.value
            timetable = loaded.2.value
            routePoints = loaded.3.value
            isFromCache = loaded.0.isFromCache || loaded.1.isFromCache || loaded.2.isFromCache || loaded.3.isFromCache
            lastUpdated = [loaded.0.fetchedAt, loaded.1.fetchedAt, loaded.2.fetchedAt, loaded.3.fetchedAt].max()
        } catch {
            loadError = "Veriler alınamadı. Bağlantınızı kontrol edip tekrar deneyin."
        }
        isLoading = false
    }

    @MainActor
    func clearCache() {
        try? cache.clear()
        lastUpdated = nil
        isFromCache = false
    }
}
