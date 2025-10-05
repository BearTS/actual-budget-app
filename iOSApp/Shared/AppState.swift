import Foundation
import Combine

final class AppState: ObservableObject {
    // --- NEW: Theme Management ---
    enum Theme: String, CaseIterable, Identifiable {
        case Dark = "Dark"
        case amoledDark = "Dark (AMOLED)"
        case systemLight = "System Light"
        var id: String { self.rawValue }
    }
    
    @Published var currentTheme: Theme {    
        didSet { UserDefaults.standard.set(currentTheme.rawValue, forKey: Keys.currentTheme) }
    }
    
    // Other properties...
    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL)
            AppLogger.shared.updateRedactionBaseURL(baseURLString)
        }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }
    @Published var syncId: String {
        didSet { UserDefaults.standard.set(syncId, forKey: Keys.syncId) }
    }
    @Published var budgetEncryptionPassword: String {
        didSet { UserDefaults.standard.set(budgetEncryptionPassword, forKey: Keys.budgetEncryptionPassword) }
    }
    @Published var isDemoMode: Bool {
        didSet { UserDefaults.standard.set(isDemoMode, forKey: Keys.isDemoMode) }
    }
    @Published var currencyCode: String {
        didSet { UserDefaults.standard.set(currencyCode, forKey: Keys.currencyCode) }
    }

    var isConfigured: Bool { isDemoMode || (!baseURLString.isEmpty && !apiKey.isEmpty && !syncId.isEmpty) }

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Keys.baseURL) ?? ""
        self.apiKey = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
        self.syncId = UserDefaults.standard.string(forKey: Keys.syncId) ?? ""
        self.budgetEncryptionPassword = UserDefaults.standard.string(forKey: Keys.budgetEncryptionPassword) ?? ""
        self.isDemoMode = UserDefaults.standard.bool(forKey: Keys.isDemoMode)
        self.currencyCode = UserDefaults.standard.string(forKey: Keys.currencyCode) ?? Locale.current.currency?.identifier ?? "USD"
        
        let savedTheme = UserDefaults.standard.string(forKey: Keys.currentTheme) ?? ""
        self.currentTheme = Theme(rawValue: savedTheme) ?? .amoledDark
        AppLogger.shared.updateRedactionBaseURL(self.baseURLString)
    }

    func resetConfiguration() {
        baseURLString = ""
        apiKey = ""
        syncId = ""
        budgetEncryptionPassword = ""
    }

    private enum Keys {
        static let baseURL = "ActualBaseURL"
        static let apiKey = "ActualAPIKey"
        static let syncId = "ActualSyncId"
        static let budgetEncryptionPassword = "ActualBudgetEncryptionPassword"
        static let isDemoMode = "ActualIsDemoMode"
        static let currencyCode = "ActualCurrencyCode"
        static let currentTheme = "ActualCurrentTheme" // New key
    }
}