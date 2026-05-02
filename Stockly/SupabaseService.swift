import Foundation

// MARK: - Supabase Config
// Store credentials in Keychain, never hardcode

extension Keychain {
    static var supabaseURL: String? {
        get { load(for: "supabase_url") }
        set {
            if let val = newValue, !val.isEmpty { save(val, for: "supabase_url") }
            else { delete(for: "supabase_url") }
        }
    }
    static var supabaseAnonKey: String? {
        get { load(for: "supabase_anon_key") }
        set {
            if let val = newValue, !val.isEmpty { save(val, for: "supabase_anon_key") }
            else { delete(for: "supabase_anon_key") }
        }
    }
}

// MARK: - DTO (matches Supabase table schema)

struct HoldingRow: Codable, Sendable {
    let id: String?
    let sym: String
    let name: String
    let shares: Double
    let cost: Double
    let stock_group: String
    let created_at: String?

    // For INSERT — no id, Supabase generates it
    init(inserting holding: HoldingLocal) {
        self.id = nil
        self.sym = holding.sym
        self.name = holding.name
        self.shares = holding.shares
        self.cost = holding.cost
        self.stock_group = holding.group.rawValue
        self.created_at = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, sym, name, shares, cost, stock_group, created_at
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Skip id and created_at on encode so Supabase auto-generates them
        try c.encode(sym,         forKey: .sym)
        try c.encode(name,        forKey: .name)
        try c.encode(shares,      forKey: .shares)
        try c.encode(cost,        forKey: .cost)
        try c.encode(stock_group, forKey: .stock_group)
    }
}

// Local model decoupled from @Model for Supabase use
struct HoldingLocal: Sendable {
    let id: String
    let sym: String
    let name: String
    let shares: Double
    let cost: Double
    let group: GroupType

    init(sym: String, name: String, shares: Double, cost: Double, group: GroupType) {
        self.id = UUID().uuidString
        self.sym = sym.uppercased()
        self.name = name
        self.shares = shares
        self.cost = cost
        self.group = group
    }

    init(row: HoldingRow) {
        self.id = row.id ?? UUID().uuidString
        self.sym = row.sym
        self.name = row.name
        self.shares = row.shares
        self.cost = row.cost
        self.group = GroupType(rawValue: row.stock_group) ?? .other
    }
}

// MARK: - Supabase Service

actor SupabaseService {
    static let shared = SupabaseService()
    private init() {}

    private var baseURL: String { Keychain.supabaseURL ?? "" }
    private var anonKey: String { Keychain.supabaseAnonKey ?? "" }
    var isConfigured: Bool { !baseURL.isEmpty && !anonKey.isEmpty }

    // MARK: - Fetch all holdings

    func fetchHoldings() async throws -> [HoldingLocal] {
        let url = try endpoint("/rest/v1/holdings?select=*&order=created_at.asc")
        let data = try await request(url: url, method: "GET")
        let rows = try JSONDecoder().decode([HoldingRow].self, from: data)
        return rows.map { HoldingLocal(row: $0) }
    }

    // MARK: - Insert holding

    func insert(_ holding: HoldingLocal) async throws {
        let url = try endpoint("/rest/v1/holdings")
        let row = HoldingRow(inserting: holding)
        let body = try JSONEncoder().encode(row)
        _ = try await request(url: url, method: "POST", body: body, prefer: "return=minimal")
    }

    func upsertHolding(sym: String, shares: Double, cost: Double) async throws {
        let url = try endpoint("/rest/v1/holdings?sym=eq.\(sym)")
        let body = try JSONSerialization.data(withJSONObject: ["shares": shares, "cost": cost])
        _ = try await request(url: url, method: "PATCH", body: body)
    }

    func delete(syms: [String]) async throws {
        guard !syms.isEmpty else { return }
        let symList = syms.map { "\"\($0)\"" }.joined(separator: ",")
        let url = try endpoint("/rest/v1/holdings?sym=in.(\(symList))")
        _ = try await request(url: url, method: "DELETE")
    }

    // MARK: - Upsert (for sync)

    func upsert(_ holdings: [HoldingLocal]) async throws {
        guard !holdings.isEmpty else { return }
        let url = try endpoint("/rest/v1/holdings")
        let rows = holdings.map { HoldingRow(inserting: $0) }
        let body = try JSONEncoder().encode(rows)
        _ = try await request(url: url, method: "POST", body: body, prefer: "resolution=merge-duplicates,return=minimal")
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) throws -> URL {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else {
            throw SupabaseError.notConfigured
        }
        return url
    }

    private func request(
        url: URL,
        method: String,
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(anonKey,              forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue("application/json",   forHTTPHeaderField: "Accept")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body   { req.httpBody = body }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
        return data
    }
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:       return "Supabase is not configured. Add your URL and key in Settings."
        case .invalidResponse:     return "Invalid response from Supabase."
        case .httpError(let c, let m): return "Supabase error \(c): \(m)"
        }
    }
}
