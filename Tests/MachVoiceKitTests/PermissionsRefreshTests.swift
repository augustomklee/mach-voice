import Testing
@testable import MachVoiceKit

@MainActor
struct PermissionsRefreshTests {
    @Test func refreshInvokesOnRefreshCallback() {
        let permissions = Permissions()
        var callCount = 0
        permissions.onRefresh = { callCount += 1 }

        permissions.refresh()

        #expect(callCount == 1)
    }

    @Test func onRefreshFiresOnEveryCall() {
        let permissions = Permissions()
        var callCount = 0
        permissions.onRefresh = { callCount += 1 }

        permissions.refresh()
        permissions.refresh()
        permissions.refresh()

        #expect(callCount == 3)
    }

    @Test func freshEventTapIsNotInstalled() {
        let tap = EventTap()
        #expect(!tap.isInstalled)
    }
}
