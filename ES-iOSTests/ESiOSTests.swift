import XCTest
@testable import ES_iOS

final class ESiOSTests: XCTestCase {
    func testCSVParserHandlesSemicolonQuotesAndTurkishCharacters() {
        let csv = """
        HAT_NO;HAT_ADI;ACIKLAMA
        5;"NARLIDERE - ÜÇKUYULAR İSKELE";"MİTHAT; PAŞA"
        """

        let document = CSVParser().parse(csv)

        XCTAssertEqual(document.headers, ["HAT_NO", "HAT_ADI", "ACIKLAMA"])
        XCTAssertEqual(document.rows.first?["HAT_ADI"], "NARLIDERE - ÜÇKUYULAR İSKELE")
        XCTAssertEqual(document.rows.first?["ACIKLAMA"], "MİTHAT; PAŞA")
    }

    func testOfficialLineMapping() {
        let csv = """
        HAT_NO;HAT_ADI;GUZERGAH_ACIKLAMA;ACIKLAMA;HAT_BASLANGIC;HAT_BITIS
        5;NARLIDERE - ÜÇKUYULAR İSKELE;MİTHAT PAŞA CAD.;;NARLIDERE;ÜÇKUYULAR İSKELE
        """

        let lines = TransitMapper(configuration: .fallback).lines(from: CSVParser().parse(csv))

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].number, "5")
        XCTAssertEqual(lines[0].start, "NARLIDERE")
    }

    func testOfficialStopMappingSplitsServingLines() {
        let csv = """
        DURAK_ID;DURAK_ADI;ENLEM;BOYLAM;DURAKTAN_GECEN_HATLAR
        10007;Bahribaba;38.415144105211;27.12772009127190;29-30
        """

        let stops = TransitMapper(configuration: .fallback).stops(from: CSVParser().parse(csv))

        XCTAssertEqual(stops.first?.servingLineNumbers, ["29", "30"])
        XCTAssertEqual(stops.first?.name, "Bahribaba")
    }

    func testTimetableCreatesOutboundAndInboundEntries() {
        let csv = """
        HAT_NO;TARIFE_ID;GIDIS_SAATI;DONUS_SAATI;SIRA;GIDIS_ENGELLI_DESTEGI;DONUS_ENGELLI_DESTEGI;BISIKLETLI_GIDIS;BISIKLETLI_DONUS;GIDIS_ELEKTRIKLI_OTOBUS;DONUS_ELEKTRIKLI_OTOBUS
        5;1;06:00;06:35;1;True;True;True;False;False;True
        """

        let entries = TransitMapper(configuration: .fallback).timetable(from: CSVParser().parse(csv))

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].direction, .outbound)
        XCTAssertEqual(entries[1].direction, .inbound)
        XCTAssertEqual(entries[0].serviceTypeLabel, "Hafta içi")
    }

    func testRouteGeometryUsesCSVOrderAsSequence() {
        let csv = """
        HAT_NO;YON;BOYLAM;ENLEM
        5;1;26.9899;38.3926
        5;1;26.9900;38.3927
        """

        let points = TransitMapper(configuration: .fallback).routePoints(from: CSVParser().parse(csv))

        XCTAssertEqual(points.map(\.sequence), [1, 2])
        XCTAssertEqual(points.first?.direction, .outbound)
    }

    func testRealtimeDecoderParsesCommaDecimalStrings() throws {
        let json = """
        [{"KalanDurakSayisi":2,"HattinYonu":1,"KoorY":"27,065335","BisikletAparatliMi":true,"KoorX":"38,47833667","EngelliMi":false,"HatNumarasi":446,"HatAdi":"EVKA","OtobusId":2043}]
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode([ApproachingBusDTO].self, from: json).first
        let arrival = dto?.arrival(stopID: "21050", timestamp: Date())

        XCTAssertEqual(arrival?.lineNumber, "446")
        XCTAssertEqual(arrival?.latitude, 38.47833667, accuracy: 0.000001)
        XCTAssertEqual(arrival?.longitude, 27.065335, accuracy: 0.000001)
    }

    func testLineSearchRanksExactNumberFirst() {
        let lines = [
            BusLine(number: "5", title: "Narlıdere", routeSummary: "", note: nil, start: "", end: "", isNightLine: false),
            BusLine(number: "50", title: "Başka Hat", routeSummary: "", note: nil, start: "", end: "", isNightLine: false)
        ]

        let result = SearchEngine().lines(lines, matching: "5")

        XCTAssertEqual(result.map(\.number), ["5", "50"])
    }

    func testStopSearchSupportsFuzzyName() {
        let stops = [
            BusStop(stopID: "10005", name: "Bahribaba", latitude: 0, longitude: 0, servingLineNumbers: []),
            BusStop(stopID: "20000", name: "Konak", latitude: 0, longitude: 0, servingLineNumbers: [])
        ]

        let result = SearchEngine().stops(stops, matching: "bahribba")

        XCTAssertEqual(result.first?.stopID, "10005")
    }

    func testFavoritesStoreDoesNotDuplicateIDs() {
        let defaults = UserDefaults(suiteName: "ESiOSTests-\(UUID().uuidString)")!
        let store = FavoritesStore(defaults: defaults)

        store.toggleLine("5")
        store.toggleLine("5")
        store.toggleLine("5")

        XCTAssertEqual(store.lineIDs, Set(["5"]))
    }
}
