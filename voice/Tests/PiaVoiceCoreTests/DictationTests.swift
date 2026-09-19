import XCTest
@testable import PiaVoiceCore

final class TranscriptionTests: XCTestCase {
    func testMultipartFields() {
        let context = Transcription.Context(languages: ["es", "en"], keywords: ["PIA"], prompt: "hola")
        let body = Transcription.multipart(audio: Data("AUDIO".utf8), filename: "a.m4a", context: context, boundary: "B")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        XCTAssertTrue(text.contains("name=\"languages[]\"\r\n\r\nes\r\n"))
        XCTAssertTrue(text.contains("name=\"languages[]\"\r\n\r\nen\r\n"))
        XCTAssertTrue(text.contains("name=\"keywords[]\"\r\n\r\nPIA\r\n"))
        XCTAssertTrue(text.contains("name=\"prompt\"\r\n\r\nhola\r\n"))
        XCTAssertTrue(text.contains("filename=\"a.m4a\"\r\nContent-Type: audio/mp4\r\n\r\nAUDIO\r\n"))
        XCTAssertTrue(text.hasSuffix("--B--\r\n"))
    }

    func testParse() {
        let result = Transcription.parse(Data(#"{"text":"Hola","languages":[{"code":"es"}],"usage":{"type":"duration","seconds":6}}"#.utf8))
        XCTAssertEqual(result, Transcription.Result(text: "Hola", seconds: 6))
        XCTAssertEqual(Transcription.parse(Data(#"{"text":"x","usage":{"type":"tokens","input_tokens":3}}"#.utf8))?.seconds, nil)
        XCTAssertNil(Transcription.parse(Data(#"{"error":{"message":"bad"}}"#.utf8)))
    }
}

final class DictationLedgerTests: XCTestCase {
    func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    func testMonthRollover() {
        var ledger = DictationLedger(month: "2026-09")
        ledger.add(seconds: 600, at: date("2026-09-14"))
        XCTAssertEqual(ledger.dollars(at: date("2026-09-20")), 0.045, accuracy: 1e-9)
        XCTAssertEqual(ledger.dollars(at: date("2026-09-20"), pendingSeconds: 60), 0.0495, accuracy: 1e-9)
        XCTAssertEqual(ledger.dollars(at: date("2026-10-01")), 0)
        ledger.add(seconds: 60, at: date("2026-10-02"))
        XCTAssertEqual(ledger, DictationLedger(month: "2026-10", seconds: 60, dictations: 1))
    }

    func testLabel() {
        XCTAssertEqual(DictationLedger.label(0), "$0.000")
        XCTAssertEqual(DictationLedger.label(0.0045), "$0.004")
        XCTAssertEqual(DictationLedger.label(1.254), "$1.25")
    }

    func testSaveAndLoad() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let ledger = DictationLedger(month: "2026-09", seconds: 12, dictations: 2)
        ledger.save(url)
        XCTAssertEqual(DictationLedger.load(url), ledger)
    }
}

final class HotkeySpecTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(HotkeySpec.parse("option+space"), HotkeySpec(keyCode: 49, modifiers: 2048, description: "option+space"))
        XCTAssertEqual(HotkeySpec.parse("Ctrl + Shift + D")?.modifiers, 4096 | 512)
        XCTAssertEqual(HotkeySpec.parse("ctrl+shift+d")?.keyCode, 2)
        XCTAssertNil(HotkeySpec.parse("space"), "a plain key would be taken from every app")
        XCTAssertNil(HotkeySpec.parse("hyper+space"))
        XCTAssertNil(HotkeySpec.parse("option+f13"))
    }
}

final class DictationBufferTests: XCTestCase {
    func testAppendingJoinsWithABlankLine() {
        XCTAssertEqual(DictationBuffer.joined(previous: "First thought.", take: "Second thought."),
                       "First thought.\n\nSecond thought.")
    }

    func testNothingToAppendToGivesJustTheTake() {
        XCTAssertEqual(DictationBuffer.joined(previous: nil, take: "Only this."), "Only this.")
        XCTAssertEqual(DictationBuffer.joined(previous: "", take: "Only this."), "Only this.")
        XCTAssertEqual(DictationBuffer.joined(previous: "  \n\n ", take: "Only this."), "Only this.")
    }

    func testSurroundingWhitespaceNeverDoublesTheGap() {
        XCTAssertEqual(DictationBuffer.joined(previous: "One.\n\n", take: "\n Two. "), "One.\n\nTwo.")
    }

    func testThreeTakesAccumulate() {
        var buffer: String? = nil
        for take in ["One.", "Two.", "Three."] {
            buffer = DictationBuffer.joined(previous: buffer, take: take)
        }
        XCTAssertEqual(buffer, "One.\n\nTwo.\n\nThree.")
    }
}

final class AppendHotkeyTests: XCTestCase {
    func testShiftVariantOfTheDefault() {
        let base = HotkeySpec.default
        let append = base.withShift
        XCTAssertEqual(append?.description, "option+shift+space")
        XCTAssertEqual(append?.keyCode, base.keyCode)
        XCTAssertEqual(append?.modifiers, base.modifiers | 512)
    }

    func testNoVariantWhenTheShortcutAlreadyUsesShift() {
        XCTAssertNil(HotkeySpec.parse("option+shift+space")!.withShift)
    }

    func testCustomShortcutKeepsItsOtherModifiers() {
        let append = HotkeySpec.parse("ctrl+cmd+j")!.withShift
        XCTAssertEqual(append?.description, "ctrl+cmd+shift+j")
        XCTAssertEqual(append?.modifiers, 4096 | 256 | 512)
    }
}

final class TalkFileTests: XCTestCase {
    func temporaryDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testPrefersTalkOverIntent() throws {
        let dir = try temporaryDir()
        try "talk".write(to: dir.appendingPathComponent("talk.md"), atomically: true, encoding: .utf8)
        try "intent".write(to: dir.appendingPathComponent("intent.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(IntentFile.locate(in: dir).lastPathComponent, "talk.md")
    }

    func testFallsBackToIntentForOlderWorks() throws {
        let dir = try temporaryDir()
        try "intent".write(to: dir.appendingPathComponent("intent.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(IntentFile.locate(in: dir).lastPathComponent, "intent.md")
    }

    func testEmptyFolderWaitsForTalk() throws {
        XCTAssertEqual(IntentFile.locate(in: try temporaryDir()).lastPathComponent, "talk.md")
    }

    func testSummaryStopsAtTheFirstBodyHeading() {
        let state = IntentFile.parse("""
        # Offline reading

        **Intention:** Read what is already synced.

        ## What we found
        - No cache today.

        ## The conversation

        ### Round 1
        1. Which one hurts? → Reading.
        """)
        XCTAssertFalse(state.summary.contains("No cache today"))
        XCTAssertTrue(state.summary.contains("Read what is already synced"))
        XCTAssertEqual(state.rounds.count, 1)
        XCTAssertEqual(state.rounds.first?.unansweredCount, 0)
    }
}
