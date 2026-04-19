import Foundation

struct CacheEntryMetadata: Codable {
    let key: String
    let fetchedAt: Date
}

final class FileCacheStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("ES-iOSCache", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(data: Data, for key: String, fetchedAt: Date = Date()) throws {
        try data.write(to: dataURL(for: key), options: .atomic)
        let metadata = CacheEntryMetadata(key: key, fetchedAt: fetchedAt)
        try encoder.encode(metadata).write(to: metadataURL(for: key), options: .atomic)
    }

    func loadData(for key: String) throws -> (Data, Date) {
        let data = try Data(contentsOf: dataURL(for: key))
        let metadata = try decoder.decode(CacheEntryMetadata.self, from: Data(contentsOf: metadataURL(for: key)))
        return (data, metadata.fetchedAt)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func dataURL(for key: String) -> URL {
        directory.appendingPathComponent(safeKey(key)).appendingPathExtension("data")
    }

    private func metadataURL(for key: String) -> URL {
        directory.appendingPathComponent(safeKey(key)).appendingPathExtension("json")
    }

    private func safeKey(_ key: String) -> String {
        key.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
    }
}

final class FavoritesStore: ObservableObject {
    @Published private(set) var lineIDs: Set<String>
    @Published private(set) var stopIDs: Set<String>

    private let defaults: UserDefaults
    private let lineKey = "favoriteLineIDs"
    private let stopKey = "favoriteStopIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lineIDs = Set(defaults.stringArray(forKey: lineKey) ?? [])
        stopIDs = Set(defaults.stringArray(forKey: stopKey) ?? [])
    }

    func toggleLine(_ id: String) {
        if lineIDs.contains(id) { lineIDs.remove(id) } else { lineIDs.insert(id) }
        defaults.set(Array(lineIDs).sorted(), forKey: lineKey)
    }

    func toggleStop(_ id: String) {
        if stopIDs.contains(id) { stopIDs.remove(id) } else { stopIDs.insert(id) }
        defaults.set(Array(stopIDs).sorted(), forKey: stopKey)
    }
}

final class RecentSearchStore: ObservableObject {
    @Published private(set) var items: [RecentSearchItem]

    private let defaults: UserDefaults
    private let key = "recentSearches"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecentSearchItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func add(_ item: RecentSearchItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        items = Array(items.prefix(10))
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
