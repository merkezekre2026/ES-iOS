import Foundation
import CoreLocation

struct BusLine: Identifiable, Codable, Hashable {
    var id: String { number }
    let number: String
    let title: String
    let routeSummary: String
    let note: String?
    let start: String
    let end: String
    let isNightLine: Bool
}

struct BusStop: Identifiable, Codable, Hashable {
    var id: String { stopID }
    let stopID: String
    let name: String
    let latitude: Double
    let longitude: Double
    let servingLineNumbers: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum Direction: Int, Codable, CaseIterable, Hashable, Identifiable {
    case outbound = 1
    case inbound = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .outbound: return "Gidiş"
        case .inbound: return "Dönüş"
        }
    }

    static func fromRouteValue(_ value: String) -> Direction {
        value.trimmingCharacters(in: .whitespacesAndNewlines) == "2" ? .inbound : .outbound
    }
}

struct TimetableEntry: Identifiable, Codable, Hashable {
    var id: String { "\(lineNumber)-\(serviceTypeID)-\(direction.rawValue)-\(sequence)-\(departureTime)" }
    let lineNumber: String
    let serviceTypeID: String
    let serviceTypeLabel: String
    let direction: Direction
    let sequence: Int
    let departureTime: String
    let wheelchairAccessible: Bool
    let bicycleSupported: Bool
    let electricBus: Bool
}

enum ArrivalSource: String, Codable, Hashable {
    case realtime = "Canlı"
    case staticSchedule = "Tarife"
}

struct StopArrival: Identifiable, Codable, Hashable {
    var id: String { "\(stopID)-\(lineNumber)-\(busID)-\(timestamp.timeIntervalSince1970)" }
    let stopID: String
    let lineNumber: String
    let lineName: String
    let busID: String
    let direction: Direction
    let remainingStopCount: Int?
    let latitude: Double?
    let longitude: Double?
    let wheelchairAccessible: Bool
    let bicycleSupported: Bool
    let timestamp: Date
    let source: ArrivalSource
}

struct VehicleLocation: Identifiable, Codable, Hashable {
    var id: String { busID }
    let busID: String
    let lineNumber: String
    let direction: Direction
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

struct RoutePoint: Identifiable, Codable, Hashable {
    var id: String { "\(lineNumber)-\(direction.rawValue)-\(sequence)" }
    let lineNumber: String
    let direction: Direction
    let latitude: Double
    let longitude: Double
    let sequence: Int
}

struct NearbyStop: Identifiable, Codable, Hashable {
    var id: String { stop.stopID }
    let stop: BusStop
    let distanceMeters: Double
}

struct CachedValue<Value> {
    let value: Value
    let fetchedAt: Date
    let isFromCache: Bool
}

enum LoadingState<Value> {
    case idle
    case loading
    case loaded(Value, isFromCache: Bool, updatedAt: Date?)
    case empty(String)
    case failed(String)
}

enum RecentSearchItem: Codable, Hashable, Identifiable {
    case line(number: String, title: String)
    case stop(id: String, name: String)

    var id: String {
        switch self {
        case .line(let number, _): return "line-\(number)"
        case .stop(let id, _): return "stop-\(id)"
        }
    }

    var title: String {
        switch self {
        case .line(let number, let title): return "\(number) \(title)"
        case .stop(let id, let name): return "\(id) \(name)"
        }
    }

    var icon: String {
        switch self {
        case .line: return "bus"
        case .stop: return "mappin.and.ellipse"
        }
    }
}
