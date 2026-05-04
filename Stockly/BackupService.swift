import Foundation
// import SwiftData  // DISABLED — Supabase is source of truth

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

//struct BackupService {
//    static func export(holdings: [HoldingLocal]) throws -> URL {
//        let backup = PortfolioBackup(
//            exportedAt: Date(),
//            version: 1,
//            holdings: holdings.map {
//                HoldingBackup(sym: $0.sym, name: $0.name, shares: $0.shares, cost: $0.cost, group: $0.group)
//            }
//        )
//        let encoder = JSONEncoder()
//        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
//        encoder.dateEncodingStrategy = .iso8601
//        let data = try encoder.encode(backup)
//        let formatter = DateFormatter()
//        formatter.dateFormat = "yyyy-MM-dd"
//        let url = FileManager.default.temporaryDirectory
//            .appendingPathComponent("stockly-backup-\(formatter.string(from: Date())).json")
//        try data.write(to: url)
//        return url
//    }
//
//    // import(from:into:) disabled — SwiftData removed
//    // Re-enable when SwiftData is restored
//}
