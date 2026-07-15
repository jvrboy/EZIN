import Foundation
import Combine

/// Tracks API token usage across all providers: tokens used, remaining, reset dates,
/// and rate-limit status. Persists to UserDefaults and aggregates across unlimited keys.
@MainActor
final class APITokenTracker: ObservableObject {
    static let shared = APITokenTracker()

    @Published var keyStats: [String: KeyUsageStats] = [:]
    @Published var providerTotals: [CredentialKey: ProviderAggregateStats] = [:]

    private let defaults = UserDefaults.standard
    private let statsKey = "api_token_tracker.stats"

    private init() { load() }

    // MARK: - Recording Usage

    /// Call this after every successful API request to track usage.
    func recordUsage(provider: CredentialKey, keyId: String, tokensUsed: Int = 0, responseHeaders: [AnyHashable: Any]? = nil) {
        let key = "\(provider.rawValue).\(keyId)"
        var stats = keyStats[key] ?? KeyUsageStats(provider: provider.rawValue, keyId: keyId)

        stats.requestsThisMinute += 1
        stats.requestsToday += 1
        stats.totalRequests += 1
        if tokensUsed > 0 {
            stats.tokensUsed += tokensUsed
        }
        stats.lastUsedAt = Date()

        // Parse rate-limit headers if available.
        if let headers = responseHeaders {
            if let remaining = headers["x-ratelimit-remaining"] as? String, let val = Int(remaining) {
                stats.rateLimitRemaining = val
            }
            if let limit = headers["x-ratelimit-limit"] as? String, let val = Int(limit) {
                stats.rateLimitTotal = val
            }
            if let resetStr = headers["x-ratelimit-reset"] as? String, let resetUnix = Double(resetStr) {
                stats.rateLimitResetsAt = Date(timeIntervalSince1970: resetUnix)
            }
            if let resetTokens = headers["x-ratelimit-tokens-remaining"] as? String, let val = Int(resetTokens) {
                stats.tokensRemaining = val
            }
        }

        keyStats[key] = stats
        recalculateProviderTotals()
        save()
    }

    /// Mark a key as rate-limited.
    func markRateLimited(provider: CredentialKey, keyId: String, retryAfter: TimeInterval? = nil) {
        let key = "\(provider.rawValue).\(keyId)"
        var stats = keyStats[key] ?? KeyUsageStats(provider: provider.rawValue, keyId: keyId)
        stats.isRateLimited = true
        stats.rateLimitedUntil = retryAfter.map { Date().addingTimeInterval($0) }
        keyStats[key] = stats
        recalculateProviderTotals()
        save()
    }

    /// Mark a key as working again after a successful request.
    func markHealthy(provider: CredentialKey, keyId: String) {
        let key = "\(provider.rawValue).\(keyId)"
        guard var stats = keyStats[key] else { return }
        stats.isRateLimited = false
        stats.rateLimitedUntil = nil
        stats.consecutiveErrors = 0
        keyStats[key] = stats
        recalculateProviderTotals()
        save()
    }

    /// Record an error for a key.
    func recordError(provider: CredentialKey, keyId: String) {
        let key = "\(provider.rawValue).\(keyId)"
        var stats = keyStats[key] ?? KeyUsageStats(provider: provider.rawValue, keyId: keyId)
        stats.consecutiveErrors += 1
        // If 5 consecutive errors, mark as unhealthy.
        if stats.consecutiveErrors >= 5 {
            stats.isHealthy = false
        }
        keyStats[key] = stats
        recalculateProviderTotals()
        save()
    }

    // MARK: - Queries

    /// Check if a key is currently usable (not rate-limited and healthy).
    func isKeyUsable(provider: CredentialKey, keyId: String) -> Bool {
        let key = "\(provider.rawValue).\(keyId)"
        guard let stats = keyStats[key] else { return true }
        if !stats.isHealthy { return false }
        if stats.isRateLimited {
            if let until = stats.rateLimitedUntil, Date() > until {
                // Rate limit has expired.
                return true
            }
            return false
        }
        return true
    }

    /// Get the best key index for a provider (the one with most remaining quota).
    func bestKeyIndex(for provider: CredentialKey, totalKeys: Int) -> Int {
        guard totalKeys > 0 else { return 0 }
        var bestIndex = 0
        var bestScore = -1

        for i in 0..<totalKeys {
            let keyId = "key_\(i)"
            let key = "\(provider.rawValue).\(keyId)"
            let stats = keyStats[key]
            let score = stats?.rateLimitRemaining ?? Int.max
            if isKeyUsable(provider: provider, keyId: keyId) && score > bestScore {
                bestScore = score
                bestIndex = i
            }
        }
        return bestIndex
    }

    /// Aggregate stats for a provider across all its keys.
    func aggregate(for provider: CredentialKey) -> ProviderAggregateStats {
        providerTotals[provider] ?? ProviderAggregateStats()
    }

    /// Reset daily counters if it's a new day.
    func checkDayRollover() {
        let calendar = Calendar.current
        var changed = false
        for (key, var stats) in keyStats {
            if let lastReset = stats.lastResetAt,
               !calendar.isDate(lastReset, inSameDayAs: Date()) {
                stats.requestsToday = 0
                stats.tokensUsed = 0
                stats.isRateLimited = false
                stats.rateLimitedUntil = nil
                stats.lastResetAt = Date()
                keyStats[key] = stats
                changed = true
            }
        }
        if changed {
            recalculateProviderTotals()
            save()
        }
    }

    // MARK: - Private

    private func recalculateProviderTotals() {
        var totals: [CredentialKey: ProviderAggregateStats] = [:]
        for (_, stats) in keyStats {
            guard let provider = CredentialKey(rawValue: stats.provider) else { continue }
            var agg = totals[provider] ?? ProviderAggregateStats()
            agg.totalKeys += 1
            agg.totalRequests += stats.totalRequests
            agg.totalTokensUsed += stats.tokensUsed
            agg.activeKeys += stats.isHealthy && !stats.isRateLimited ? 1 : 0
            agg.rateLimitedKeys += stats.isRateLimited ? 1 : 0
            if let remaining = stats.rateLimitRemaining {
                agg.totalRemainingQuota += remaining
            }
            if let resetsAt = stats.rateLimitResetsAt,
               agg.earliestReset == nil || resetsAt < agg.earliestReset! {
                agg.earliestReset = resetsAt
            }
            totals[provider] = agg
        }
        providerTotals = totals
    }

    private func save() {
        if let data = try? JSONEncoder().encode(keyStats) {
            defaults.set(data, forKey: statsKey)
        }
    }

    private func load() {
        if let data = defaults.data(forKey: statsKey),
           let decoded = try? JSONDecoder().decode([String: KeyUsageStats].self, from: data) {
            keyStats = decoded
            recalculateProviderTotals()
        }
    }

    func resetAll() {
        keyStats.removeAll()
        providerTotals.removeAll()
        defaults.removeObject(forKey: statsKey)
    }
}

// MARK: - Models

struct KeyUsageStats: Codable {
    var provider: String
    var keyId: String
    var requestsThisMinute: Int = 0
    var requestsToday: Int = 0
    var totalRequests: Int = 0
    var tokensUsed: Int = 0
    var tokensRemaining: Int?
    var rateLimitRemaining: Int?
    var rateLimitTotal: Int?
    var rateLimitResetsAt: Date?
    var isRateLimited: Bool = false
    var rateLimitedUntil: Date?
    var isHealthy: Bool = true
    var consecutiveErrors: Int = 0
    var lastUsedAt: Date?
    var lastResetAt: Date = Date()
}

struct ProviderAggregateStats: Codable {
    var totalKeys: Int = 0
    var activeKeys: Int = 0
    var rateLimitedKeys: Int = 0
    var totalRequests: Int = 0
    var totalTokensUsed: Int = 0
    var totalRemainingQuota: Int = 0
    var earliestReset: Date?

    var summary: String {
        if totalKeys == 0 { return "No keys configured" }
        var parts: [String] = []
        parts.append("\(activeKeys)/\(totalKeys) active")
        if totalRequests > 0 { parts.append("\(totalRequests) req") }
        if totalTokensUsed > 0 { parts.append("\(totalTokensUsed) tok") }
        if totalRemainingQuota > 0 { parts.append("\(totalRemainingQuota) left") }
        if let reset = earliestReset {
            let diff = reset.timeIntervalSince(Date())
            if diff > 0 {
                let mins = Int(diff / 60)
                parts.append("resets in \(mins)m")
            }
        }
        return parts.joined(separator: " · ")
    }
}
