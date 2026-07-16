import Foundation

/// Provider validation results for AI API key testing
struct ProviderValidationResult: Identifiable {
    let id = UUID()
    let provider: CredentialKey
    let isValid: Bool
    let message: String
    let latencyMs: Int?
    let modelUsed: String?
    let capabilities: [String]?
}

/// Batch validation status for multiple providers
struct ProviderBatchStatus {
    var results: [ProviderValidationResult] = []
    var isValidating = false
    var currentProvider: CredentialKey?
}

/// Validates AI provider API keys with connectivity and compatibility tests
/// Tests Nvidia NIM, Cerebras, and FreeModel endpoints for compatibility
@MainActor
final class ProviderValidator: ObservableObject {
    static let shared = ProviderValidator()

    @Published var batchStatus = ProviderBatchStatus()
    @Published var lastValidationResults: [ProviderValidationResult] = []

    private init() {}

    // MARK: - Batch Validation

    /// Validate all configured provider keys (NIM, Cerebras, FreeModel priority)
    func validateAllProviders() async {
        batchStatus.isValidating = true
        batchStatus.results = []
        batchStatus.currentProvider = nil

        var providersToTest = Set(APIKeyStore.shared.activeProviders)
        providersToTest.formUnion([.nvidianim, .cerebras, .freemodel])
        if CredentialStore.shared.has(.customEndpoint) { providersToTest.insert(.customEndpoint) }

        if providersToTest.isEmpty {
            batchStatus.results.append(ProviderValidationResult(
                provider: .openAI, isValid: false,
                message: "No AI keys configured. Add a key or a custom endpoint first.",
                latencyMs: nil, modelUsed: nil, capabilities: nil
            ))
        }

        for provider in providersToTest.sorted(by: { $0.rawValue < $1.rawValue }) {
            batchStatus.currentProvider = provider
            if provider == .customEndpoint {
                let result = await validateCustomEndpoint(startTime: Date())
                batchStatus.results.append(result)
                continue
            }
            let keys = APIKeyStore.shared.keys(for: provider)
            if keys.isEmpty {
                batchStatus.results.append(ProviderValidationResult(
                    provider: provider, isValid: false,
                    message: "No key stored for \(provider.display).",
                    latencyMs: nil, modelUsed: nil, capabilities: nil
                ))
                continue
            }
            for key in keys {
                let result = await validateKey(provider: provider, key: key)
                batchStatus.results.append(result)
                // Small delay between tests to avoid rate limiting
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        batchStatus.currentProvider = nil
        batchStatus.isValidating = false
        lastValidationResults = batchStatus.results
    }

    /// Validate a single provider key
    func validateKey(provider: CredentialKey, key: String) async -> ProviderValidationResult {
        let startTime = Date()

        switch provider {
        case .nvidianim:
            return await validateNvidiaNIM(key: key, startTime: startTime)
        case .cerebras:
            return await validateCerebras(key: key, startTime: startTime)
        case .freemodel:
            return await validateFreeModel(key: key, startTime: startTime)
        case .customEndpoint:
            return await validateCustomEndpoint(startTime: startTime)
        default:
            return ProviderValidationResult(
                provider: provider,
                isValid: false,
                message: "Provider not supported for validation",
                latencyMs: nil,
                modelUsed: nil,
                capabilities: nil
            )
        }
    }

    // MARK: - Nvidia NIM Validation

    private func validateNvidiaNIM(key: String, startTime: Date) async -> ProviderValidationResult {
        let testPrompt = "Reply with exactly: NIM_VALIDATION_SUCCESS"

        do {
            let result = try await callNvidiaNIM(key: key, prompt: testPrompt, maxTokens: 30)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)

            if result.lowercased().contains("nim_validation_success") {
                return ProviderValidationResult(
                    provider: .nvidianim,
                    isValid: true,
                    message: "Nvidia NIM connection successful",
                    latencyMs: latency,
                    modelUsed: "meta/llama-3.1-405b-instruct",
                    capabilities: ["chat", "code", "analysis", "long_context"]
                )
            } else {
                return ProviderValidationResult(
                    provider: .nvidianim,
                    isValid: false,
                    message: "Nvidia NIM responded but returned unexpected content",
                    latencyMs: latency,
                    modelUsed: "meta/llama-3.1-405b-instruct",
                    capabilities: nil
                )
            }
        } catch let error as AIProviderError {
            return ProviderValidationResult(
                provider: .nvidianim,
                isValid: false,
                message: "Nvidia NIM error: \(error.localizedDescription)",
                latencyMs: Int(Date().timeIntervalSince(startTime) * 1000),
                modelUsed: nil,
                capabilities: nil
            )
        } catch {
            return ProviderValidationResult(
                provider: .nvidianim,
                isValid: false,
                message: "Nvidia NIM connection failed: \(error.localizedDescription)",
                latencyMs: Int(Date().timeIntervalSince(startTime) * 1000),
                modelUsed: nil,
                capabilities: nil
            )
        }
    }

    private func callNvidiaNIM(key: String, prompt: String, maxTokens: Int) async throws -> String {
        let urlStr = "https://integrate.api.nvidia.com/v1/chat/completions"
        let model = "meta/llama-3.1-405b-instruct"

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens,
            "temperature": 0.1
        ]

        return try await callProviderAPI(url: urlStr, key: key, body: body)
    }

    // MARK: - Cerebras Validation

    private func validateCerebras(key: String, startTime: Date) async -> ProviderValidationResult {
        let testPrompt = "Reply with exactly: CEREBRAS_VALIDATION_SUCCESS"

        do {
            let result = try await callCerebras(key: key, prompt: testPrompt, maxTokens: 30)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)

            if result.lowercased().contains("cerebras_validation_success") {
                return ProviderValidationResult(
                    provider: .cerebras,
                    isValid: true,
                    message: "Cerebras connection successful",
                    latencyMs: latency,
                    modelUsed: "llama-3.3-70b",
                    capabilities: ["chat", "fast_inference", "cost_effective"]
                )
            } else {
                return ProviderValidationResult(
                    provider: .cerebras,
                    isValid: false,
                    message: "Cerebras responded but returned unexpected content",
                    latencyMs: latency,
                    modelUsed: "llama-3.3-70b",
                    capabilities: nil
                )
            }
        } catch let error as AIProviderError {
            return ProviderValidationResult(
                provider: .cerebras,
                isValid: false,
                message: "Cerebras error: \(error.localizedDescription)",
                latencyMs: Int(Date().timeIntervalSince(startTime) * 1000),
                modelUsed: nil,
                capabilities: nil
            )
        } catch {
            return ProviderValidationResult(
                provider: .cerebras,
                isValid: false,
                message: "Cerebras connection failed: \(error.localizedDescription)",
                latencyMs: Int(Date().timeIntervalSince(startTime) * 1000),
                modelUsed: nil,
                capabilities: nil
            )
        }
    }

    private func callCerebras(key: String, prompt: String, maxTokens: Int) async throws -> String {
        let urlStr = "https://api.cerebras.ai/v1/chat/completions"
        let model = "llama-3.3-70b"

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens,
            "temperature": 0.1
        ]

        return try await callProviderAPI(url: urlStr, key: key, body: body)
    }

    // MARK: - FreeModel Validation

    private func validateFreeModel(key: String, startTime: Date) async -> ProviderValidationResult {
        let testPrompt = "Reply with exactly: FREEMODEL_VALIDATION_SUCCESS"

        do {
            let result = try await callFreeModel(key: key, prompt: testPrompt, maxTokens: 30)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)

            if result.lowercased().contains("freemodel_validation_success") {
                return ProviderValidationResult(
                    provider: .freemodel,
                    isValid: true,
                    message: "FreeModel connection successful",
                    latencyMs: latency,
                    modelUsed: "gpt-3.5-turbo",
                    capabilities: ["chat", "fast_inference", "free_tier"]
                )
            } else {
                return ProviderValidationResult(
                    provider: .freemodel,
                    isValid: false,
                    message: "FreeModel responded but returned unexpected content",
                    latencyMs: latency,
                    modelUsed: "gpt-3.5-turbo",
                    capabilities: nil
                )
            }
        } catch let error as AIProviderError {
            return ProviderValidationResult(
                provider: .freemodel,
                isValid: false,
                message: "FreeModel error: \(error.localizedDescription)",
                latencyMs: Int(Date().timeIntervalSince(startTime) * 1000),
                modelUsed: nil,
                capabilities: nil
            )
        } catch {
            return ProviderValidationResult(
                provider: .freemodel,
                isValid: false,
                message: "FreeModel connection failed: \(error.localizedDescription)",
                latencyMs: Int(Date().timeIntervalSince(startTime) * 1000),
                modelUsed: nil,
                capabilities: nil
            )
        }
    }

    private func callFreeModel(key: String, prompt: String, maxTokens: Int) async throws -> String {
        let urlStr = "https://api.freemodel.dev/v1/chat/completions"
        let model = "gpt-3.5-turbo"

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens,
            "temperature": 0.1
        ]

        return try await callProviderAPI(url: urlStr, key: key, body: body)
    }

    // MARK: - Custom endpoint validation

    private func validateCustomEndpoint(startTime: Date) async -> ProviderValidationResult {
        guard let stored = CredentialStore.shared.value(for: .customEndpoint), !stored.isEmpty else {
            return ProviderValidationResult(provider: .customEndpoint, isValid: false, message: "No custom endpoint stored", latencyMs: nil, modelUsed: nil, capabilities: nil)
        }
        let parts = stored.split(separator: "|", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let body: [String: Any] = [
            "model": "local-llm",
            "messages": [["role": "user", "content": "Reply with exactly: ENDPOINT_VALIDATION_SUCCESS"]],
            "max_tokens": 30,
            "temperature": 0.1
        ]
        do {
            let content = try await callProviderAPI(url: parts[0], key: parts.count > 1 ? parts[1] : "", body: body)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            let ok = content.lowercased().contains("endpoint_validation_success") || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return ProviderValidationResult(
                provider: .customEndpoint,
                isValid: ok,
                message: ok ? "Custom endpoint responded" : "Custom endpoint returned an empty response",
                latencyMs: latency,
                modelUsed: "local-llm",
                capabilities: ["self_hosted", "openai_compatible", "real_llm"]
            )
        } catch {
            return ProviderValidationResult(
                provider: .customEndpoint,
                isValid: false,
                message: "Custom endpoint failed: \(error.localizedDescription)",
                latencyMs: Int(Date().timeIntervalSince(startTime) * 1000),
                modelUsed: nil,
                capabilities: nil
            )
        }
    }

    // MARK: - Generic API Caller

    private func callProviderAPI(url: String, key: String, body: [String: Any]) async throws -> String {
        guard let urlObj = URL(string: url) else {
            throw AIProviderError.http("Invalid URL")
        }

        var request = URLRequest(url: urlObj)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.http("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.http("HTTP \(httpResponse.statusCode): \(errorMsg.prefix(100))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.parse
        }

        return content
    }

    // MARK: - Helper Methods

    /// Get summary of all validation results
    func validationSummary() -> String {
        guard !lastValidationResults.isEmpty else {
            return "No validation results. Run validation from Settings."
        }

        let valid = lastValidationResults.filter { $0.isValid }
        let invalid = lastValidationResults.filter { !$0.isValid }

        var summary = "Provider Validation Results:\n"
        summary += "Valid: \(valid.count) | Invalid: \(invalid.count)\n\n"

        for result in lastValidationResults {
            let status = result.isValid ? "[OK]" : "[FAIL]"
            summary += "\(status) \(result.provider.rawValue): \(result.message)"
            if let latency = result.latencyMs {
                summary += " (Latency: \(latency)ms)"
            }
            if let caps = result.capabilities, !caps.isEmpty {
                summary += " [\(caps.joined(separator: ", "))]"
            }
            summary += "\n"
        }

        return summary
    }

    /// Previously this deleted every key for any provider with one failed validation.
    /// That was destructive: rate limits/network blips could wipe all credentials. Keep keys;
    /// surface failures to the user instead.
    func removeInvalidKeys() {
        // Intentionally no-op. Invalid keys are reported in lastValidationResults.
    }
}
