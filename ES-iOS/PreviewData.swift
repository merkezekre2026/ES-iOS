import Foundation
import SwiftUI

enum PreviewData {
    static let line = BusLine(number: "5", title: "NARLIDERE - ÜÇKUYULAR İSKELE", routeSummary: "MİTHAT PAŞA CAD. - F.ALTAY AKT.", note: nil, start: "NARLIDERE", end: "ÜÇKUYULAR İSKELE", isNightLine: false)

    static let stop = BusStop(stopID: "10005", name: "Bahribaba", latitude: 38.415268, longitude: 27.127639, servingLineNumbers: ["32"])

    static let timetable = TimetableEntry(lineNumber: "5", serviceTypeID: "1", serviceTypeLabel: "Hafta içi", direction: .outbound, sequence: 1, departureTime: "06:00", wheelchairAccessible: true, bicycleSupported: true, electricBus: false)
}

#Preview("Line Row") {
    NavigationStack {
        List {
            LineRow(line: PreviewData.line)
            StopRow(stop: PreviewData.stop)
            TimetableRow(entry: PreviewData.timetable)
        }
    }
}
