import Testing
@testable import DockToggle

@Suite("MinimizeMenuMatch")
struct MinimizeMenuMatchTests {

    // MARK: - isVerifiedMinimizeAll

    @Test("matches the standard Minimize All binding")
    func matchesStandardMinimizeAll() {
        #expect(MinimizeMenuMatch.isVerifiedMinimizeAll(
            commandCharacter: "m", modifiers: 2, identifier: "miniaturizeAll:"))
    }

    @Test("command character is case-insensitive")
    func caseInsensitiveCommandCharacter() {
        #expect(MinimizeMenuMatch.isVerifiedMinimizeAll(
            commandCharacter: "M", modifiers: 2, identifier: "miniaturizeAll:"))
    }

    @Test("rejects the same chord without the verified identifier")
    func rejectsWithoutIdentifier() {
        // Some other app-defined action can also bind ⌥⌘M — the identifier is what proves
        // it is really Minimize All.
        #expect(!MinimizeMenuMatch.isVerifiedMinimizeAll(
            commandCharacter: "M", modifiers: 2, identifier: "customAction:"))
    }

    @Test("rejects the right identifier with the wrong modifiers")
    func rejectsWrongModifiers() {
        #expect(!MinimizeMenuMatch.isVerifiedMinimizeAll(
            commandCharacter: "M", modifiers: 0, identifier: "miniaturizeAll:"))
    }

    @Test("rejects a different command character entirely")
    func rejectsWrongCharacter() {
        #expect(!MinimizeMenuMatch.isVerifiedMinimizeAll(
            commandCharacter: "N", modifiers: 2, identifier: "miniaturizeAll:"))
    }

    @Test("rejects nil fields")
    func rejectsNilFields() {
        #expect(!MinimizeMenuMatch.isVerifiedMinimizeAll(
            commandCharacter: nil, modifiers: nil, identifier: nil))
    }

    // MARK: - isPlainMinimize

    @Test("matches plain Command-M")
    func matchesPlainMinimize() {
        #expect(MinimizeMenuMatch.isPlainMinimize(commandCharacter: "m", modifiers: 0))
    }

    @Test("rejects Command-M with an extra modifier")
    func rejectsExtraModifier() {
        #expect(!MinimizeMenuMatch.isPlainMinimize(commandCharacter: "M", modifiers: 2))
    }

    @Test("rejects a different command character")
    func rejectsDifferentCharacter() {
        #expect(!MinimizeMenuMatch.isPlainMinimize(commandCharacter: "N", modifiers: 0))
    }
}
