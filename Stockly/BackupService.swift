import Foundation
import SwiftData

// MARK: - Codable DTO (separate from @Model since @Model can't be Codable)

struct HoldingBackup: Codable {
    let sym: String
    let name: String
    let shares: Double
    let cost: Double
    let group: GroupType
}

struct PortfolioBackup: Codable {
    let exportedAt: Date
    let version: Int
    let holdings: [HoldingBackup]
}

// MARK: - Backup Service

struct BackupService {

    static func export(holdings: [Holding]) throws -> URL {
        let backup = PortfolioBackup(
            exportedAt: Date(),
            version: 1,
            holdings: holdings.map {
                HoldingBackup(sym: $0.sym, name: $0.name, shares: $0.shares, cost: $0.cost, group: $0.group)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "stockly-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    static func `import`(from url: URL, into context: ModelContext) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PortfolioBackup.self, from: data)

        // Fetch existing symbols to avoid duplicates
        let existing = (try? context.fetch(FetchDescriptor<Holding>()))?.map { $0.sym } ?? []

        var imported = 0
        for h in backup.holdings where !existing.contains(h.sym) {
            context.insert(Holding(sym: h.sym, name: h.name, shares: h.shares, cost: h.cost, group: h.group))
            imported += 1
        }
        try context.save()
        return imported
    }
}
