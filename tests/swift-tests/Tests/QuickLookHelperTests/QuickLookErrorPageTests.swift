import XCTest
@testable import QuickLookHelpers

final class QuickLookErrorPageTests: XCTestCase {

    // MARK: - Markdown escaping

    func testEscapingNeutralizesMarkdownAndHTMLSyntax() {
        let hostile = "*_`<script>alert(\"&\")</script> [link](x) #{}end"
        let escaped = QuickLookErrorPage.escaped(hostile)
        XCTAssertEqual(
            escaped,
            "\\*\\_\\`\\<script\\>alert\\(\\\"\\&\\\"\\)\\<\\/script\\> \\[link\\]\\(x\\) \\#\\{\\}end"
        )
        // …so no raw HTML or emphasis markup survives.
        XCTAssertFalse(escaped.contains("<script>"))
        XCTAssertFalse(escaped.contains("[link]"))
    }

    func testEscapingLeavesPlainWordsAlone() {
        XCTAssertEqual(QuickLookErrorPage.escaped("notes 2026 v1 final"), "notes 2026 v1 final")
    }

    // MARK: - Page content

    private let readError = CocoaError(.fileReadNoPermission)

    func testPageIncludesFileNameErrorAndDomain() {
        let url = URL(fileURLWithPath: "/Users/ada/Documents/notes *draft*.md")
        let markdown = QuickLookErrorPage.makeMarkdown(for: readError, fileURL: url)
        XCTAssertTrue(markdown.contains("notes \\*draft\\*\\.md"))
        XCTAssertTrue(markdown.contains(QuickLookErrorPage.escaped(readError.localizedDescription)))
        XCTAssertTrue(markdown.contains("NSCocoaErrorDomain"))
        XCTAssertTrue(markdown.contains("\(readError.errorCode)"))
        XCTAssertTrue(markdown.contains(QuickLookErrorPage.escaped("/Users/ada/Documents")))
    }

    // The hint logic prefixes against the real user's containers root
    // (resolved via getpwuid, as in production), so build test paths from
    // the same home instead of a fabricated one.
    private var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    func testContainerPathGetsContainerHint() {
        let url = URL(fileURLWithPath:
            "\(realHome)/Library/Containers/com.tencent.xinWeChat/Data/Documents/files/report.md")
        let markdown = QuickLookErrorPage.makeMarkdown(for: readError, fileURL: url)
        XCTAssertTrue(markdown.contains("sandbox container"))
    }

    func testLookalikeContainerPathGetsGenericHintOnly() {
        // Contains "/Library/Containers/" as a substring but not under the
        // user's real home — must not get the container hint.
        let url = URL(fileURLWithPath: "/tmp/Library/Containers/report.md")
        let markdown = QuickLookErrorPage.makeMarkdown(for: readError, fileURL: url)
        XCTAssertFalse(markdown.contains("sandbox container"))
        XCTAssertTrue(markdown.contains("Double-click"))
    }

    func testOtherUsersContainerPathGetsGenericHintOnly() {
        // Under a different user's home — same substring, wrong prefix.
        let url = URL(fileURLWithPath: "/Users/someone-else/Library/Containers/app/report.md")
        let markdown = QuickLookErrorPage.makeMarkdown(for: readError, fileURL: url)
        XCTAssertFalse(markdown.contains("sandbox container"))
        XCTAssertTrue(markdown.contains("Double-click"))
    }

    func testRegularPathGetsGenericHintOnly() {
        let url = URL(fileURLWithPath: "\(realHome)/Documents/report.md")
        let markdown = QuickLookErrorPage.makeMarkdown(for: readError, fileURL: url)
        XCTAssertFalse(markdown.contains("sandbox container"))
        XCTAssertTrue(markdown.contains("Double-click"))
    }
}
