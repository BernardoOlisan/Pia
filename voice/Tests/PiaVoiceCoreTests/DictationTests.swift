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

/// The say script is what stands between a long answer and a session that silently rejects it.
final class VoiceSayScriptTests: XCTestCase {
    func run(_ work: URL, _ text: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("scripts/voice-say.sh").path,
            work.path, text,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testEveryLineStaysUnderTheAppendLimit() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let inbox = work.appendingPathComponent("logs/voice-inbox.txt")
        FileManager.default.createFile(atPath: inbox.path, contents: Data())

        try run(work, "Una frase corta.")
        try run(work, Array(repeating: "Esta es una oracion larga de prueba.", count: 120).joined(separator: " "))

        let lines = try String(contentsOf: inbox, encoding: .utf8)
            .split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertGreaterThan(lines.count, 2, "the long one must have been split")
        for line in lines {
            XCTAssertLessThanOrEqual(line.count, 1400, "a single append over the limit is dropped whole")
        }
        XCTAssertEqual(lines.first, "Una frase corta.")
    }

    func testRefusesAWorkWithNoVoiceRunning() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("scripts/voice-say.sh").path,
            work.path, "hola",
        ]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
    }
}
