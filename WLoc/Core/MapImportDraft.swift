import Foundation

/// A result belongs to one revision of the input, never to a later pasted link.
struct MapImportDraft {
    var name = ""
    var latitude = ""
    var longitude = ""
    var system = CoordinateSystem.wgs84
    var source = "手动输入"
    var warning: String?
    private(set) var revision = UUID()

    @discardableResult
    mutating func reset() -> UUID {
        name = ""
        latitude = ""
        longitude = ""
        system = .wgs84
        source = "手动输入"
        warning = nil
        revision = UUID()
        return revision
    }
    @discardableResult
    mutating func accept(_ location: ParsedLocation, for token: UUID) -> Bool {
        guard token == revision else { return false }
        name = location.name
        latitude = String(location.coordinate.latitude)
        longitude = String(location.coordinate.longitude)
        system = location.system
        source = location.source
        warning = location.warning
        return true
    }
    mutating func select(_ location: ParsedLocation) {
        let token = reset()
        accept(location, for: token)
    }
    var normalized: Coordinate? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              (try? validateCoordinates(lat, lon)) != nil else { return nil }
        return system.toWGS(Coordinate(latitude: lat, longitude: lon))
    }
}
