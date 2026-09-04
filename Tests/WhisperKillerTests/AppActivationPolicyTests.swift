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

    @Test("primary status click restores an existing standalone window")
    func primaryStatusClickRestoresWindow() {
        #expect(
            statusItemClickAction(for: .primary, hasStandaloneWindow: true)
                == .restoreStandaloneWindow
        )
    }

    @Test("primary status click opens the menu without standalone windows")
    func primaryStatusClickWithoutWindowOpensMenu() {
        #expect(
            statusItemClickAction(for: .primary, hasStandaloneWindow: false)
                == .toggleMenu
        )
    }

    @Test("secondary status click opens the menu without restoring a window")
    func secondaryStatusClickAlwaysOpensMenu() {
        #expect(
            statusItemClickAction(for: .secondary, hasStandaloneWindow: true)
                == .toggleMenu
        )
        #expect(
            statusItemClickAction(for: .secondary, hasStandaloneWindow: false)
                == .toggleMenu
        )
    }
}
