# ES-iOS

ES-iOS is a native Universal SwiftUI app for ESHOT bus information in İzmir on iPhone and iPad. It uses official İzmir Metropolitan Municipality open data sources for lines, stops, static schedules, route geometry, nearby stops, and available realtime bus position/approaching-stop APIs.

## Requirements

- Xcode 15.4 or newer
- iOS 17.0 or newer
- No third-party packages

Open `ES-iOS.xcodeproj`, select the `ES-iOS` scheme, and run on an iPhone or iPad simulator or device. iPhone keeps the compact tab-based experience, while iPad uses an adaptive sidebar and detail layout in portrait and landscape. Nearby stops require location permission, so a real device gives the best result.

## Data Sources

All URLs are configured in `ES-iOS/Resources/EndpointConfiguration.json`.

- `eshot-otobus-hatlari.csv`: ESHOT line number, title, start/end, and route summary.
- `eshot-otobus-duraklari.csv`: stop ID, stop name, coordinates, and serving line numbers.
- `eshot-otobus-hareketsaatleri.csv`: static timetable rows by line, service type, direction, and departure time.
- `eshot-otobus-hat-guzergahlari.csv`: route geometry points by line and direction.
- `noktayayakinduraklar`: official nearby-stop API using WGS84 coordinates.
- `duragayaklasanotobusler`, `hattinyaklasanotobusleri`, and `hatotobuskonumlari`: realtime İztek APIs for approaching buses and vehicle positions.

`EndpointConfiguration.swift` loads the bundled JSON and falls back to built-in official URLs if the resource cannot be read. To move to a staging/proxy service later, update the JSON file without changing UI code.

## Parsing And Normalization

The production datasource is CSV/open API based. A robust semicolon CSV parser handles quoted fields, CRLF, malformed rows, UTF-8 Turkish text, and diagnostic collection. The mappers normalize official columns into:

- `BusLine`
- `BusStop`
- `TimetableEntry`
- `RoutePoint`
- `StopArrival`
- `VehicleLocation`

`TARIFE_ID` is mapped through `serviceTypeLabels` in `EndpointConfiguration.json`. Defaults are `1 = Hafta içi`, `2 = Cumartesi`, and `3 = Pazar`; unknown IDs display as `Tarife {id}`.

No official GTFS dataset was found while planning, so production uses the official CSV/API feeds. `GTFSParser` is included as dormant, unit-testable support for future GTFS files.

## Offline And Cache Strategy

Static CSV responses are cached in Application Support through `FileCacheStore`. If the network fails, cached static data is shown and labeled as `Önbellekten` or `Çevrimdışı veri` where relevant. Favorites and recent searches use `UserDefaults`.

Realtime data is intentionally separate from static timetable data and is labeled `Canlı`. Realtime calls are not silently mixed into static schedules. If realtime data is unavailable, the UI keeps static timetable and serving-line information usable.

The Settings screen includes source attribution, the latest loaded timestamp, and a cache clear action. Clearing cache does not remove favorites.

## Architecture

- SwiftUI + MVVM
- `AppContainer` owns dependency injection and shared app state.
- `TransportDataServiceProtocol` makes services unit-testable.
- `TransportDataService` uses async/await, `URLSession`, Codable JSON decoders, CSV parsing, and cache fallback.
- `LocationService` wraps CoreLocation permission and current location.
- Screens are organized adaptively: compact width uses tab-based `NavigationStack`s, and regular width uses `NavigationSplitView` with a sidebar for Home, Lines, Stops, Nearby, Favorites, and Settings.

## Tests

The `ES-iOSTests` target covers:

- CSV parser behavior
- Official CSV header mapping
- Timetable direction/service type normalization
- Route point sequencing
- Realtime JSON decoding with comma decimal coordinates
- Line and stop search ranking
- Favorites persistence without duplicates

Run tests from Xcode with `Product > Test`.

## Future Enhancements

- Home screen widgets for favorite stops
- Siri Shortcuts for “next bus at this stop”
- Apple Watch nearby-stop glance
- Live Activities for selected stop/line tracking
- Push notifications for route alarms
- More precise route-stop ordering if an official stop sequence feed becomes available
