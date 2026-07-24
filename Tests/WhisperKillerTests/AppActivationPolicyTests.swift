import Testing
@testable import WhisperKiller

@MainActor
@Suite("App activation policy")
struct AppActivationPolicyTests {
    @Test("menu-bar-only mode stays accessory without standalone windows")
    func menuBarOnlyWithoutStandaloneWindows() {
        #expect(
            !requiresRegularActivationPolicy(
                configuredMode: .menuBarOnly,
                standaloneWindowCount: 0
            )
        )
    }

    @Test("menu-bar-only mode becomes regular while a standalone window is open")
    func menuBarOnlyWithStandaloneWindow() {
        #expect(
            requiresRegularActivationPolicy(
                configuredMode: .menuBarOnly,
                standaloneWindowCount: 1
            )
        )
    }

    @Test("configured Dock modes stay regular without standalone windows")
    func configuredDockModes() {
        #expect(
            requiresRegularActivationPolicy(
                configuredMode: .dockAndMenuBar,
                standaloneWindowCount: 0
            )
        )
        #expect(
            requiresRegularActivationPolicy(
                configuredMode: .dockOnly,
                standaloneWindowCount: 0
            )
        )
    }
}
