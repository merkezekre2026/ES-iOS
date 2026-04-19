import SwiftUI
import MapKit
import CoreLocation

struct RootTabView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(container: container)
                    .navigationDestination(for: BusLine.self) { LineDetailView(line: $0, container: container) }
                    .navigationDestination(for: BusStop.self) { StopDetailView(stop: $0, container: container) }
            }
            .tabItem { Label("Ana Sayfa", systemImage: "house") }

            NavigationStack {
                LineSearchView(container: container)
                    .navigationDestination(for: BusLine.self) { LineDetailView(line: $0, container: container) }
            }
            .tabItem { Label("Hatlar", systemImage: "bus") }

            NavigationStack {
                StopSearchView(container: container)
                    .navigationDestination(for: BusStop.self) { StopDetailView(stop: $0, container: container) }
            }
            .tabItem { Label("Duraklar", systemImage: "mappin.and.ellipse") }

            NavigationStack {
                NearbyStopsView(container: container)
                    .navigationDestination(for: BusStop.self) { StopDetailView(stop: $0, container: container) }
            }
            .tabItem { Label("Yakınımda", systemImage: "location") }

            NavigationStack {
                FavoritesView(container: container)
                    .navigationDestination(for: BusLine.self) { LineDetailView(line: $0, container: container) }
                    .navigationDestination(for: BusStop.self) { StopDetailView(stop: $0, container: container) }
            }
            .tabItem { Label("Favoriler", systemImage: "star") }

            NavigationStack {
                SettingsView(container: container)
            }
            .tabItem { Label("Ayarlar", systemImage: "gearshape") }
        }
        .task { await container.bootstrap() }
    }
}

struct HomeView: View {
    @EnvironmentObject private var recents: RecentSearchStore
    @EnvironmentObject private var location: LocationService
    @ObservedObject private var container: AppContainer
    @StateObject private var viewModel: HomeViewModel

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: HomeViewModel(container: container))
    }

    var body: some View {
        List {
            if container.isLoading {
                skeletonSection
            }

            if let error = container.loadError {
                ErrorRow(message: error) { Task { await container.bootstrap(forceRefresh: true) } }
            }

            Section {
                TextField("Hat veya durak ara", text: $viewModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.vertical, 6)
            }

            if !viewModel.query.isEmpty {
                SearchPreviewSection(lines: viewModel.matchingLines, stops: viewModel.matchingStops)
            }

            Section("Favori Hatlar") {
                if viewModel.favoriteLines.isEmpty {
                    EmptyStateRow(icon: "star", title: "Henüz favori hat yok", message: "Sık kullandığınız hatları detay ekranından ekleyin.")
                } else {
                    ForEach(viewModel.favoriteLines.prefix(6)) { LineRow(line: $0) }
                }
            }

            Section("Favori Duraklar") {
                if viewModel.favoriteStops.isEmpty {
                    EmptyStateRow(icon: "mappin", title: "Henüz favori durak yok", message: "Durak detayında yıldız simgesini kullanın.")
                } else {
                    ForEach(viewModel.favoriteStops.prefix(6)) { StopRow(stop: $0) }
                }
            }

            Section("Yakındaki Duraklar") {
                Button {
                    location.request()
                    Task { await viewModel.loadNearbyPreview() }
                } label: {
                    Label("Yakındaki durakları göster", systemImage: "location.circle")
                }
                NearbyStateRows(state: viewModel.nearby)
            }

            Section("Son Aramalar") {
                if recents.items.isEmpty {
                    EmptyStateRow(icon: "clock", title: "Son arama yok", message: "Açtığınız hat ve duraklar burada görünür.")
                } else {
                    ForEach(recents.items) { item in
                        Label(item.title, systemImage: item.icon)
                    }
                }
            }
        }
        .navigationTitle("ES-iOS")
        .refreshable { await container.bootstrap(forceRefresh: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await container.bootstrap(forceRefresh: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Verileri yenile")
            }
        }
    }

    private var skeletonSection: some View {
        Section {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.2))
                    .frame(height: 54)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

struct SearchPreviewSection: View {
    let lines: [BusLine]
    let stops: [BusStop]

    var body: some View {
        Section("Arama Sonuçları") {
            ForEach(lines) { LineRow(line: $0) }
            ForEach(stops) { StopRow(stop: $0) }
            if lines.isEmpty && stops.isEmpty {
                EmptyStateRow(icon: "magnifyingglass", title: "Sonuç yok", message: "Hat numarası, hat adı, durak numarası veya durak adı deneyin.")
            }
        }
    }
}

struct LineSearchView: View {
    @ObservedObject private var container: AppContainer
    @StateObject private var viewModel: LineSearchViewModel

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: LineSearchViewModel(container: container))
    }

    var body: some View {
        List {
            if container.lines.isEmpty && container.isLoading {
                ProgressView("Hatlar yükleniyor")
            } else if viewModel.results.isEmpty {
                EmptyStateRow(icon: "bus", title: "Hat bulunamadı", message: "Hat numarası veya güzergah adıyla arayın.")
            } else {
                ForEach(viewModel.results) { LineRow(line: $0) }
            }
        }
        .navigationTitle("Hat Ara")
        .searchable(text: $viewModel.query, prompt: "Hat numarası veya adı")
        .refreshable { await container.bootstrap(forceRefresh: true) }
    }
}

struct StopSearchView: View {
    @ObservedObject private var container: AppContainer
    @StateObject private var viewModel: StopSearchViewModel

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: StopSearchViewModel(container: container))
    }

    var body: some View {
        List {
            if container.stops.isEmpty && container.isLoading {
                ProgressView("Duraklar yükleniyor")
            } else if viewModel.results.isEmpty {
                EmptyStateRow(icon: "mappin.and.ellipse", title: "Durak bulunamadı", message: "Durak numarası veya adıyla arayın.")
            } else {
                ForEach(viewModel.results) { StopRow(stop: $0) }
            }
        }
        .navigationTitle("Durak Ara")
        .searchable(text: $viewModel.query, prompt: "Durak numarası veya adı")
        .refreshable { await container.bootstrap(forceRefresh: true) }
    }
}

struct LineDetailView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var recents: RecentSearchStore
    @StateObject private var viewModel: LineDetailViewModel

    init(line: BusLine, container: AppContainer) {
        _viewModel = StateObject(wrappedValue: LineDetailViewModel(line: line, container: container))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(viewModel.line.number)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading) {
                            Text(viewModel.line.title).font(.headline)
                            Text("\(viewModel.line.start) - \(viewModel.line.end)").foregroundStyle(.secondary)
                        }
                    }
                    if !viewModel.line.routeSummary.isEmpty {
                        Text(viewModel.line.routeSummary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Yön ve Tarife") {
                Picker("Yön", selection: $viewModel.direction) {
                    ForEach(Direction.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                if !viewModel.serviceTypes.isEmpty {
                    Picker("Tarife", selection: $viewModel.selectedServiceTypeID) {
                        ForEach(viewModel.serviceTypes, id: \.id) { service in
                            Text(service.label).tag(service.id)
                        }
                    }
                }
            }

            Section("Yaklaşan Hareket Saatleri") {
                if viewModel.upcomingDepartures.isEmpty {
                    EmptyStateRow(icon: "clock.badge.exclamationmark", title: "Saat bulunamadı", message: "Bu yön ve tarife için hareket saati yok.")
                } else {
                    ForEach(viewModel.upcomingDepartures) { entry in
                        TimetableRow(entry: entry)
                    }
                }
            }

            Section("Canlı Araç Konumları") {
                Button {
                    Task { await viewModel.loadVehicles() }
                } label: {
                    Label("Canlı konumları yenile", systemImage: "dot.radiowaves.left.and.right")
                }
                VehicleStateRows(state: viewModel.vehicles)
            }

            Section("Hat Durakları") {
                if viewModel.routeStops.isEmpty {
                    EmptyStateRow(icon: "mappin.slash", title: "Durak listesi yok", message: "Açık veri içinde bu hatta bağlı durak bulunamadı.")
                } else {
                    ForEach(viewModel.routeStops) { StopRow(stop: $0) }
                }
            }
        }
        .navigationTitle("Hat \(viewModel.line.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggleLine(viewModel.line.number)
                } label: {
                    Image(systemName: favorites.lineIDs.contains(viewModel.line.number) ? "star.fill" : "star")
                }
                .accessibilityLabel("Favori hat")
            }
        }
        .task {
            recents.add(.line(number: viewModel.line.number, title: viewModel.line.title))
            await viewModel.loadVehicles()
        }
    }
}

struct StopDetailView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var recents: RecentSearchStore
    @StateObject private var viewModel: StopDetailViewModel

    init(stop: BusStop, container: AppContainer) {
        _viewModel = StateObject(wrappedValue: StopDetailViewModel(stop: stop, container: container))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.stop.name).font(.title3.weight(.semibold))
                    Text("Durak No: \(viewModel.stop.stopID)").foregroundStyle(.secondary)
                }
            }

            Section("Canlı Yaklaşan Otobüsler") {
                Button {
                    Task { await viewModel.loadArrivals() }
                } label: {
                    Label("Canlı bilgiyi yenile", systemImage: "arrow.clockwise.circle")
                }
                ArrivalStateRows(state: viewModel.arrivals)
            }

            Section("Bu Duraktan Geçen Hatlar") {
                if viewModel.servingLines.isEmpty {
                    EmptyStateRow(icon: "bus", title: "Hat bilgisi yok", message: "Bu durak için hat eşleşmesi bulunamadı.")
                } else {
                    ForEach(viewModel.servingLines) { LineRow(line: $0) }
                }
            }

            Section("Harita") {
                Map {
                    Marker(viewModel.stop.name, coordinate: viewModel.stop.coordinate)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .navigationTitle(viewModel.stop.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggleStop(viewModel.stop.stopID)
                } label: {
                    Image(systemName: favorites.stopIDs.contains(viewModel.stop.stopID) ? "star.fill" : "star")
                }
                .accessibilityLabel("Favori durak")
            }
        }
        .task {
            recents.add(.stop(id: viewModel.stop.stopID, name: viewModel.stop.name))
            await viewModel.loadArrivals()
        }
    }
}

struct NearbyStopsView: View {
    @EnvironmentObject private var location: LocationService
    @ObservedObject private var container: AppContainer
    @StateObject private var viewModel: NearbyStopsViewModel

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: NearbyStopsViewModel(container: container))
    }

    var body: some View {
        List {
            Section {
                Button {
                    location.request()
                    Task { await viewModel.load() }
                } label: {
                    Label("Konumumu kullan", systemImage: "location.fill")
                }
            }
            NearbyStateRows(state: viewModel.state)
        }
        .navigationTitle("Yakındaki Duraklar")
        .task {
            if location.currentLocation != nil {
                await viewModel.load()
            }
        }
    }
}

struct FavoritesView: View {
    @ObservedObject private var container: AppContainer
    @EnvironmentObject private var favorites: FavoritesStore

    init(container: AppContainer) {
        self.container = container
    }

    var body: some View {
        List {
            Section("Favori Hatlar") {
                let lines = container.lines.filter { favorites.lineIDs.contains($0.number) }
                if lines.isEmpty {
                    EmptyStateRow(icon: "star", title: "Favori hat yok", message: "Hat detayından favori ekleyebilirsiniz.")
                } else {
                    ForEach(lines) { LineRow(line: $0) }
                }
            }
            Section("Favori Duraklar") {
                let stops = container.stops.filter { favorites.stopIDs.contains($0.stopID) }
                if stops.isEmpty {
                    EmptyStateRow(icon: "mappin", title: "Favori durak yok", message: "Durak detayından favori ekleyebilirsiniz.")
                } else {
                    ForEach(stops) { StopRow(stop: $0) }
                }
            }
        }
        .navigationTitle("Favoriler")
    }
}

struct SettingsView: View {
    @ObservedObject private var container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    var body: some View {
        List {
            Section("Veri Durumu") {
                LabeledContent("Son güncelleme", value: container.lastUpdated?.shortUpdatedText ?? "Henüz yok")
                LabeledContent("Kaynak", value: container.isFromCache ? "Önbellekten" : "Canlı veri")
                Button(role: .destructive) {
                    container.clearCache()
                } label: {
                    Label("Önbelleği temizle", systemImage: "trash")
                }
            }

            Section("Kaynaklar") {
                Text(container.configuration.attribution)
                Link("İzmir Açık Veri Portalı", destination: URL(string: "https://acikveri.bizizmir.com")!)
                Link("ESHOT", destination: URL(string: "https://www.eshot.gov.tr")!)
            }

            Section("Hakkında") {
                LabeledContent("Uygulama", value: "ES-iOS")
                LabeledContent("Sürüm", value: "1.0")
                Text("Gelecek geliştirmeler: widget, Siri Kestirmeleri, Apple Watch, canlı etkinlikler ve gelişmiş hat alarmı.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ayarlar")
    }
}

struct LineRow: View {
    let line: BusLine

    var body: some View {
        NavigationLink(value: line) {
            HStack(spacing: 12) {
                Text(line.number)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 54)
                    .padding(.vertical, 8)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.title).font(.headline)
                    Text(line.routeSummary.isEmpty ? "\(line.start) - \(line.end)" : line.routeSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct StopRow: View {
    let stop: BusStop

    var body: some View {
        NavigationLink(value: stop) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stop.name).font(.headline)
                    Spacer()
                    Text(stop.stopID).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if !stop.servingLineNumbers.isEmpty {
                    Text(stop.servingLineNumbers.prefix(8).joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct TimetableRow: View {
    let entry: TimetableEntry

    var body: some View {
        HStack {
            Text(entry.departureTime)
                .font(.title3.monospacedDigit().weight(.semibold))
            Spacer()
            Label(entry.sourceLabel, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.wheelchairAccessible { Image(systemName: "figure.roll") }
            if entry.bicycleSupported { Image(systemName: "bicycle") }
            if entry.electricBus { Image(systemName: "bolt.fill") }
        }
    }
}

private extension TimetableEntry {
    var sourceLabel: String { "Tarife" }
}

struct ArrivalStateRows: View {
    let state: LoadingState<[StopArrival]>

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Canlı bilgi alınıyor")
        case .loaded(let arrivals, let isFromCache, let updatedAt):
            if isFromCache { StatusPill(text: "Önbellekten") }
            if let updatedAt { Text("Son güncelleme \(updatedAt.shortUpdatedText)").font(.caption).foregroundStyle(.secondary) }
            ForEach(arrivals) { arrival in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(arrival.lineNumber) \(arrival.lineName)").font(.headline)
                        Text(arrival.remainingStopCount.map { "\($0) durak kaldı" } ?? "Konum bilgisi var").foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: arrival.source.rawValue)
                }
            }
        case .empty(let message):
            EmptyStateRow(icon: "dot.radiowaves.left.and.right", title: "Canlı veri yok", message: message)
        case .failed(let message):
            EmptyStateRow(icon: "wifi.exclamationmark", title: "Bağlantı sorunu", message: message)
        }
    }
}

struct VehicleStateRows: View {
    let state: LoadingState<[VehicleLocation]>

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Araç konumları alınıyor")
        case .loaded(let vehicles, _, let updatedAt):
            if let updatedAt { Text("Son güncelleme \(updatedAt.shortUpdatedText)").font(.caption).foregroundStyle(.secondary) }
            ForEach(vehicles.prefix(8)) { vehicle in
                HStack {
                    Label("Otobüs \(vehicle.busID)", systemImage: "bus.fill")
                    Spacer()
                    Text(vehicle.direction.displayName).foregroundStyle(.secondary)
                }
            }
        case .empty(let message):
            EmptyStateRow(icon: "bus", title: "Canlı konum yok", message: message)
        case .failed(let message):
            EmptyStateRow(icon: "wifi.exclamationmark", title: "Canlı veri alınamadı", message: message)
        }
    }
}

struct NearbyStateRows: View {
    let state: LoadingState<[NearbyStop]>

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Yakındaki duraklar aranıyor")
        case .loaded(let stops, let isFromCache, let updatedAt):
            if isFromCache { StatusPill(text: "Yerel durak verisi") }
            if let updatedAt { Text("Son güncelleme \(updatedAt.shortUpdatedText)").font(.caption).foregroundStyle(.secondary) }
            ForEach(stops) { nearby in
                NavigationLink(value: nearby.stop) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(nearby.stop.name).font(.headline)
                            Text("Durak No: \(nearby.stop.stopID)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(distanceText(nearby.distanceMeters))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .empty(let message):
            EmptyStateRow(icon: "location.slash", title: "Konum gerekli", message: message)
        case .failed(let message):
            EmptyStateRow(icon: "wifi.exclamationmark", title: "Yakındaki duraklar alınamadı", message: message)
        }
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }
}

struct EmptyStateRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct ErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Veri alınamadı", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message).foregroundStyle(.secondary)
                Button("Tekrar dene", action: retry)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 8)
        }
    }
}

struct StatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.12), in: Capsule())
    }
}
