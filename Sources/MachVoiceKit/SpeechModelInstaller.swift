import Foundation
import Speech

/// Manages the installation of the en_US Speech Model.
@MainActor
final class SpeechModelInstaller: ObservableObject {
    @Published private(set) var installationState: InstallationState = .notStarted
    @Published private(set) var progress: Double = 0.0

    private let locale = Locale(identifier: "en_US")

    enum InstallationState: Equatable {
        case notStarted
        case installing
        case installed
        case failed(String)
    }

    /// Check if the model is already installed and install if needed.
    func installIfNeeded() async {
        guard case .notStarted = installationState else { return }

        // Reserve the locale first
        let reservationResult = await reserveLocale()
        guard reservationResult else {
            installationState = .failed("Failed to reserve locale")
            return
        }

        // Check if already installed
        let status = await AssetInventory.status(forModules: [SpeechEngine.makeTranscriber(locale: locale)])
        if status == .installed {
            installationState = .installed
            print("Speech model already available")
            return
        }

        // Install the model
        await install()
    }

    /// Reserve the en_US locale for Speech recognition.
    private func reserveLocale() async -> Bool {
        do {
            try await AssetInventory.reserve(locale: locale)
            print("Reserved locale: \(locale.identifier)")
            return true
        } catch {
            print("Failed to reserve locale: \(error)")
            return false
        }
    }

    /// Install the Speech Model.
    private func install() async {
        installationState = .installing

        do {
            // Create a transcriber instance to use as the module
            let transcriber = SpeechEngine.makeTranscriber(locale: locale)

            // Create an installation request
            let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])

            guard let request else {
                installationState = .failed("Asset installation request is not available")
                return
            }

            // Observe progress via KVO
            let observation = request.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor in
                    self?.progress = progress.fractionCompleted
                }
            }

            // Download and install
            try await request.downloadAndInstall()
            observation.invalidate()
            installationState = .installed
            print("Speech model installed successfully")

        } catch {
            installationState = .failed(error.localizedDescription)
            print("Failed to install Speech model: \(error)")
        }
    }
}