import Foundation

/// Gemini CLI does not currently write local usage/rate-limit logs on disk
/// (only auth/config state), so there is nothing to read yet. This stays as
/// a stub so the ring shows "Not available" instead of a fake number, and can
/// be wired up the moment Gemini CLI exposes usage data locally or via API.
enum GeminiUsageEngine {
    static func computeSnapshot() -> Void? {
        return nil
    }
}
