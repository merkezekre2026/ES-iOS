import Foundation

struct EndpointConfiguration: Codable {
    let linesCSVURL: URL
    let stopsCSVURL: URL
    let timetableCSVURL: URL
    let routeGeometryCSVURL: URL
    let nearbyStopsURLTemplate: String
    let approachingBusesURLTemplate: String
    let lineApproachingStopURLTemplate: String
    let lineVehiclesURLTemplate: String
    let requestTimeoutSeconds: TimeInterval
    let realtimeStaleAfterSeconds: TimeInterval
    let serviceTypeLabels: [String: String]
    let attribution: String

    static func load(bundle: Bundle = .main) -> EndpointConfiguration {
        guard let url = bundle.url(forResource: "EndpointConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(EndpointConfiguration.self, from: data) else {
            return .fallback
        }
        return config
    }

    func serviceTypeLabel(for id: String) -> String {
        serviceTypeLabels[id] ?? "Tarife \(id)"
    }

    func nearbyStopsURL(latitude: Double, longitude: Double) throws -> URL {
        try makeURL(from: nearbyStopsURLTemplate, replacements: [
            "{lat}": String(latitude),
            "{lon}": String(longitude)
        ])
    }

    func approachingBusesURL(stopID: String) throws -> URL {
        try makeURL(from: approachingBusesURLTemplate, replacements: ["{stopId}": stopID])
    }

    func lineApproachingStopURL(lineID: String, stopID: String) throws -> URL {
        try makeURL(from: lineApproachingStopURLTemplate, replacements: [
            "{lineId}": lineID,
            "{stopId}": stopID
        ])
    }

    func lineVehiclesURL(lineID: String) throws -> URL {
        try makeURL(from: lineVehiclesURLTemplate, replacements: ["{lineId}": lineID])
    }

    private func makeURL(from template: String, replacements: [String: String]) throws -> URL {
        let rendered = replacements.reduce(template) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
        guard let url = URL(string: rendered) else { throw URLError(.badURL) }
        return url
    }

    static let fallback = EndpointConfiguration(
        linesCSVURL: URL(string: "https://openfiles.izmir.bel.tr/211488/docs/eshot-otobus-hatlari.csv")!,
        stopsCSVURL: URL(string: "https://openfiles.izmir.bel.tr/211488/docs/eshot-otobus-duraklari.csv")!,
        timetableCSVURL: URL(string: "https://openfiles.izmir.bel.tr/211488/docs/eshot-otobus-hareketsaatleri.csv")!,
        routeGeometryCSVURL: URL(string: "https://openfiles.izmir.bel.tr/211488/docs/eshot-otobus-hat-guzergahlari.csv")!,
        nearbyStopsURLTemplate: "https://openapi.izmir.bel.tr/api/ibb/cbs/noktayayakinduraklar?x={lon}&y={lat}&inCoordSys=EPSG:4326&outCoordSys=EPSG:4326",
        approachingBusesURLTemplate: "https://openapi.izmir.bel.tr/api/iztek/duragayaklasanotobusler/{stopId}",
        lineApproachingStopURLTemplate: "https://openapi.izmir.bel.tr/api/iztek/hattinyaklasanotobusleri/{lineId}/{stopId}",
        lineVehiclesURLTemplate: "https://openapi.izmir.bel.tr/api/iztek/hatotobuskonumlari/{lineId}",
        requestTimeoutSeconds: 20,
        realtimeStaleAfterSeconds: 90,
        serviceTypeLabels: ["1": "Hafta içi", "2": "Cumartesi", "3": "Pazar"],
        attribution: "Veriler İzmir Büyükşehir Belediyesi Açık Veri Portalı ve ESHOT/İzmir İnovasyon ve Teknoloji A.Ş. açık servislerinden alınır."
    )
}
