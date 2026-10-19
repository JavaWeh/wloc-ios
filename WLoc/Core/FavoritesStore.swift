import Foundation

/// Keeps corrupt input recoverable and blocks writes if recovery cannot be made.
final class FavoritesStore {
    private let file: URL
    private let options: Data.WritingOptions
    private(set) var recoveryFile: URL?
    private(set) var canWrite = false
    init(file: URL, options: Data.WritingOptions = [.atomic]) {
        self.file = file
        self.options = options
    }
    func load() throws -> [Place] {
        canWrite = false
        guard FileManager.default.fileExists(atPath: file.path) else { canWrite = true; return [] }
        let data = try Data(contentsOf: file)
        do {
            let places = try JSONDecoder().decode([Place].self, from: data)
            try Self.validate(places)
            canWrite = true
            return places
        } catch {
            let backup = file.deletingLastPathComponent().appendingPathComponent("places-recovery-\(UUID().uuidString).json")
            // copyItem refuses to overwrite an existing backup.
            try FileManager.default.copyItem(at: file, to: backup)
            recoveryFile = backup
            canWrite = true
            return []
        }
    }
    func save(_ places: [Place]) throws {
        guard canWrite else { throw WLocError.storageReadOnly }
        try Self.validate(places)
        try JSONEncoder().encode(places).write(to: file, options: options)
    }
    private static func validate(_ places: [Place]) throws {
        guard Set(places.map(\.id)).count == places.count else { throw WLocError.invalidFavorites }
        for place in places { try place.validate() }
    }
}
