import SwiftUI

enum AppPhase: Equatable {
    case login, onboarding, main
}

/// Session, persona, saved checks and AI settings. Persisted in UserDefaults (prototype).
@Observable
final class AppState {
    var phase: AppPhase = .login
    var persona: Persona { didSet { persist() } }
    var records: [PriceCheckRecord] { didSet { persist() } }
    var geminiKey: String { didSet { defaults.set(geminiKey, forKey: Keys.geminiKey) } }
    var geminiModel: String { didSet { defaults.set(geminiModel, forKey: Keys.geminiModel) } }

    let currency = CurrencyService()

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let persona = "candor.persona"
        static let records = "candor.records"
        static let signedIn = "candor.signedIn"
        static let geminiKey = "candor.geminiKey"
        static let geminiModel = "candor.geminiModel"
    }

    init() {
        let d = UserDefaults.standard
        let decoder = JSONDecoder()
        persona = d.data(forKey: Keys.persona).flatMap { try? decoder.decode(Persona.self, from: $0) } ?? Persona()
        records = d.data(forKey: Keys.records).flatMap { try? decoder.decode([PriceCheckRecord].self, from: $0) } ?? []
        let savedKey = d.string(forKey: Keys.geminiKey) ?? ""
        geminiKey = savedKey.isEmpty ? Secrets.geminiAPIKey : savedKey
        geminiModel = d.string(forKey: Keys.geminiModel) ?? "gemini-2.5-flash"
        if d.bool(forKey: Keys.signedIn) {
            phase = persona.isComplete ? .main : .onboarding
        }
    }

    // MARK: Derived

    var hasGemini: Bool { !geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var totalFlaggedINR: Double { records.reduce(0) { $0 + $1.overchargeINR } }
    var overchargesCaught: Int { records.filter { $0.overchargeINR > 0 }.count }

    func homeAmount(_ inr: Double) -> String {
        currency.format(inr: inr, in: persona.homeCurrency)
    }

    // MARK: Session

    /// Prototype session: nothing is verified. `phone` and `email` are kept only for the method that used them.
    func signIn(with method: SignInMethod, phone: String = "", email: String? = nil) {
        var updated = persona
        updated.signInMethod = method
        updated.phone = phone
        updated.email = email
        persona = updated
        defaults.set(true, forKey: Keys.signedIn)
        phase = persona.isComplete ? .main : .onboarding
    }

    func completeOnboarding() {
        persona.isComplete = true
        phase = .main
    }

    func signOut() {
        defaults.set(false, forKey: Keys.signedIn)
        phase = .login
    }

    func record(_ record: PriceCheckRecord) {
        records.insert(record, at: 0)
    }

    func resetStats() {
        records.removeAll()
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(persona) { defaults.set(data, forKey: Keys.persona) }
        if let data = try? encoder.encode(records) { defaults.set(data, forKey: Keys.records) }
    }
}
