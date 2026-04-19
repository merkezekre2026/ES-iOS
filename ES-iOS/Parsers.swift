import Foundation

struct CSVParseDiagnostic: Codable, Hashable {
    let row: Int
    let message: String
}

struct CSVDocument {
    let headers: [String]
    let rows: [[String: String]]
    let diagnostics: [CSVParseDiagnostic]
}

struct CSVParser {
    var delimiter: Character = ";"

    func parse(_ text: String) -> CSVDocument {
        let records = parseRecords(text)
        guard let headerRecord = records.first else {
            return CSVDocument(headers: [], rows: [], diagnostics: [])
        }

        let headers = headerRecord.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var diagnostics: [CSVParseDiagnostic] = []
        var rows: [[String: String]] = []

        for (offset, record) in records.dropFirst().enumerated() {
            let rowNumber = offset + 2
            if record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            if record.count != headers.count {
                diagnostics.append(CSVParseDiagnostic(row: rowNumber, message: "Beklenen \(headers.count) sütun, gelen \(record.count)."))
            }
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = index < record.count ? record[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
            rows.append(row)
        }

        return CSVDocument(headers: headers, rows: rows, diagnostics: diagnostics)
    }

    private func parseRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        process(character: next, row: &row, field: &field, records: &records, inQuotes: &inQuotes)
                    }
                } else {
                    inQuotes.toggle()
                }
            } else {
                process(character: character, row: &row, field: &field, records: &records, inQuotes: &inQuotes)
            }
        }

        row.append(field)
        if !row.isEmpty {
            records.append(row)
        }
        return records
    }

    private func process(character: Character, row: inout [String], field: inout String, records: inout [[String]], inQuotes: inout Bool) {
        if character == delimiter, !inQuotes {
            row.append(field)
            field = ""
        } else if (character == "\n" || character == "\r"), !inQuotes {
            if character == "\n" || !field.isEmpty || !row.isEmpty {
                row.append(field)
                records.append(row)
                row = []
                field = ""
            }
        } else {
            field.append(character)
        }
    }
}

struct TransitMapper {
    let configuration: EndpointConfiguration

    func lines(from document: CSVDocument) -> [BusLine] {
        document.rows.compactMap { row in
            guard let number = row["HAT_NO"], !number.isEmpty else { return nil }
            let title = row["HAT_ADI"] ?? ""
            return BusLine(
                number: number,
                title: title,
                routeSummary: row["GUZERGAH_ACIKLAMA"] ?? "",
                note: (row["ACIKLAMA"] ?? "").nilIfBlank,
                start: row["HAT_BASLANGIC"] ?? "",
                end: row["HAT_BITIS"] ?? "",
                isNightLine: title.localizedCaseInsensitiveContains("GECE") || title.localizedCaseInsensitiveContains("BAYKUŞ")
            )
        }
        .uniqued(on: \.number)
        .sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    }

    func stops(from document: CSVDocument) -> [BusStop] {
        document.rows.compactMap { row in
            guard let id = row["DURAK_ID"], !id.isEmpty,
                  let latitude = Double.normalized(row["ENLEM"]),
                  let longitude = Double.normalized(row["BOYLAM"]) else { return nil }
            let lines = (row["DURAKTAN_GECEN_HATLAR"] ?? "")
                .split(whereSeparator: { $0 == "-" || $0 == "," || $0 == " " })
                .map(String.init)
                .filter { !$0.isEmpty }
            return BusStop(stopID: id, name: row["DURAK_ADI"] ?? "", latitude: latitude, longitude: longitude, servingLineNumbers: lines)
        }
        .uniqued(on: \.stopID)
        .sorted { $0.stopID.localizedStandardCompare($1.stopID) == .orderedAscending }
    }

    func timetable(from document: CSVDocument) -> [TimetableEntry] {
        document.rows.flatMap { row -> [TimetableEntry] in
            guard let lineNumber = row["HAT_NO"], !lineNumber.isEmpty else { return [] }
            let serviceTypeID = row["TARIFE_ID"] ?? ""
            let sequence = Int(row["SIRA"] ?? "") ?? 0
            let serviceTypeLabel = configuration.serviceTypeLabel(for: serviceTypeID)
            var entries: [TimetableEntry] = []
            if let outbound = (row["GIDIS_SAATI"] ?? "").validTime {
                entries.append(TimetableEntry(
                    lineNumber: lineNumber,
                    serviceTypeID: serviceTypeID,
                    serviceTypeLabel: serviceTypeLabel,
                    direction: .outbound,
                    sequence: sequence,
                    departureTime: outbound,
                    wheelchairAccessible: Bool.csv(row["GIDIS_ENGELLI_DESTEGI"]),
                    bicycleSupported: Bool.csv(row["BISIKLETLI_GIDIS"]),
                    electricBus: Bool.csv(row["GIDIS_ELEKTRIKLI_OTOBUS"])
                ))
            }
            if let inbound = (row["DONUS_SAATI"] ?? "").validTime {
                entries.append(TimetableEntry(
                    lineNumber: lineNumber,
                    serviceTypeID: serviceTypeID,
                    serviceTypeLabel: serviceTypeLabel,
                    direction: .inbound,
                    sequence: sequence,
                    departureTime: inbound,
                    wheelchairAccessible: Bool.csv(row["DONUS_ENGELLI_DESTEGI"]),
                    bicycleSupported: Bool.csv(row["BISIKLETLI_DONUS"]),
                    electricBus: Bool.csv(row["DONUS_ELEKTRIKLI_OTOBUS"])
                ))
            }
            return entries
        }
    }

    func routePoints(from document: CSVDocument) -> [RoutePoint] {
        var counters: [String: Int] = [:]
        return document.rows.compactMap { row in
            guard let lineNumber = row["HAT_NO"],
                  let latitude = Double.normalized(row["ENLEM"]),
                  let longitude = Double.normalized(row["BOYLAM"]) else { return nil }
            let direction = Direction.fromRouteValue(row["YON"] ?? "1")
            let key = "\(lineNumber)-\(direction.rawValue)"
            let sequence = (counters[key] ?? 0) + 1
            counters[key] = sequence
            return RoutePoint(lineNumber: lineNumber, direction: direction, latitude: latitude, longitude: longitude, sequence: sequence)
        }
    }
}

struct GTFSBundle {
    let routes: CSVDocument?
    let stops: CSVDocument?
    let trips: CSVDocument?
    let stopTimes: CSVDocument?
    let calendar: CSVDocument?
}

struct GTFSParser {
    private let parser = CSVParser(delimiter: ",")

    func parse(files: [String: String]) -> GTFSBundle {
        GTFSBundle(
            routes: files["routes.txt"].map(parser.parse),
            stops: files["stops.txt"].map(parser.parse),
            trips: files["trips.txt"].map(parser.parse),
            stopTimes: files["stop_times.txt"].map(parser.parse),
            calendar: files["calendar.txt"].map(parser.parse)
        )
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var validTime: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.contains(":") else { return nil }
        return trimmed
    }

    func normalizedForSearch() -> String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .lowercased(with: Locale(identifier: "tr_TR"))
    }
}

extension Double {
    static func normalized(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
}

extension Bool {
    static func csv(_ value: String?) -> Bool {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["true", "1", "evet", "yes"].contains(normalized)
    }
}

extension Array {
    func uniqued<ID: Hashable>(on keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen = Set<ID>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
