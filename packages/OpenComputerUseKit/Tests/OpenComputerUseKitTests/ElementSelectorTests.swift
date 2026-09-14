import XCTest
@testable import OpenComputerUseKit

final class ElementSelectorTests: XCTestCase {
    // MARK: - Parsing

    func testSelectorParsesRoleAndNameForms() throws {
        let primary = try ElementSelector.parse("button[name=检查变更]")
        XCTAssertEqual(primary.role, "button")
        XCTAssertEqual(primary.name, "检查变更")

        let nameOnly = try ElementSelector.parse("[name=返回]")
        XCTAssertNil(nameOnly.role)
        XCTAssertEqual(nameOnly.name, "返回")

        let splitGroups = try ElementSelector.parse("[role=textbox][name=用途]")
        XCTAssertEqual(splitGroups.role, "textbox")
        XCTAssertEqual(splitGroups.name, "用途")

        let commaForm = try ElementSelector.parse("[role=textbox, name=用途]")
        XCTAssertEqual(commaForm.role, "textbox")
        XCTAssertEqual(commaForm.name, "用途")

        let spaceForm = try ElementSelector.parse("[role=textbox name=用途]")
        XCTAssertEqual(spaceForm.role, "textbox")
        XCTAssertEqual(spaceForm.name, "用途")

        let bareName = try ElementSelector.parse("用途")
        XCTAssertNil(bareName.role)
        XCTAssertEqual(bareName.name, "用途")

        let attributeOnly = try ElementSelector.parse("name=交付目标 1")
        XCTAssertEqual(attributeOnly.name, "交付目标 1")

        let quoted = try ElementSelector.parse("textbox[name=\"交付目标 1\"]")
        XCTAssertEqual(quoted.name, "交付目标 1")
    }

    func testSelectorRejectsMalformedInput() {
        for raw in ["", "   ", "[name=]", "[role=textbox]", "button[name=用途] 额外", "[size=3][name=用途]"] {
            XCTAssertThrowsError(try ElementSelector.parse(raw), raw) { error in
                XCTAssertNotNil((error as? ElementSelectorParseError)?.errorDescription, raw)
            }
        }
    }

    // MARK: - Role matching

    func testSelectorMatchesAxisRolesAliasesAndLocalizedRoleText() {
        XCTAssertTrue(selectorRoleMatches(requested: "textfield", role: "AXTextField", roleText: "文本栏"))
        XCTAssertTrue(selectorRoleMatches(requested: "AXTextField", role: "AXTextField", roleText: "文本栏"))
        XCTAssertTrue(selectorRoleMatches(requested: "textbox", role: "AXTextArea", roleText: "文本输入区"))
        XCTAssertTrue(selectorRoleMatches(requested: "combobox", role: "AXComboBox", roleText: "组合框"))
        XCTAssertTrue(selectorRoleMatches(requested: "text", role: "AXStaticText", roleText: "文本"))
        // The snapshot renders localized role text; copying it must work too.
        XCTAssertTrue(selectorRoleMatches(requested: "列表框", role: "AXListBox", roleText: "列表框"))
        XCTAssertFalse(selectorRoleMatches(requested: "button", role: "AXTextField", roleText: "文本栏"))
    }

    // MARK: - Resolution

    func testSelectorMatchesByTitleDescriptionValueIdentifierAndPlaceholder() {
        let byTitle = candidate(index: 1, role: "AXTextField", names: ["标识"])
        let byDescription = candidate(index: 2, role: "AXTextField", names: ["用途"])
        let byValue = candidate(index: 3, role: "AXStaticText", names: ["草稿"])
        let byIdentifier = candidate(index: 4, role: "AXTextField", names: ["resource-name"])
        let byPlaceholder = candidate(index: 5, role: "AXTextField", names: ["请输入名称"])

        XCTAssertEqual(resolve("textfield[name=标识]", [byTitle]), .matched(1))
        XCTAssertEqual(resolve("textbox[name=用途]", [byDescription]), .matched(2))
        XCTAssertEqual(resolve("text[name=草稿]", [byValue]), .matched(3))
        XCTAssertEqual(resolve("[name=resource-name]", [byIdentifier]), .matched(4))
        XCTAssertEqual(resolve("textfield[name=请输入名称]", [byPlaceholder]), .matched(5))
    }

    func testSelectorMatchesMarkdownRenderedLinkNames() {
        let link = candidate(index: 7, role: "AXLink", names: ["[返回](https://example.com/docs)"])
        XCTAssertEqual(resolve("link[name=返回]", [link]), .matched(7))
    }

    func testSelectorPrefersExactMatchOverPrefixMatch() {
        let exact = candidate(index: 10, role: "AXStaticText", names: ["草稿"])
        let prefixOnly = candidate(index: 11, role: "AXStaticText", names: ["草稿箱"])

        XCTAssertEqual(resolve("text[name=草稿]", [prefixOnly, exact]), .matched(10))
    }

    func testSelectorFallsBackToUniquePrefixMatch() {
        let only = candidate(index: 12, role: "AXStaticText", names: ["交付目标 1"])
        XCTAssertEqual(resolve("text[name=交付目标]", [only]), .matched(12))
    }

    func testSelectorKeepsTheOutermostChromiumTextNode() {
        // Chromium reports a listbox option as a wrapper node plus a text leaf.
        let option: [ElementSelectorCandidate] = [
            candidate(index: 16, role: "AXListBox", names: []),
            candidate(index: 19, role: "AXStaticText", names: ["草稿"], parentIndex: 16),
            candidate(index: 20, role: "AXStaticText", names: ["草稿"], parentIndex: 19),
        ]

        XCTAssertEqual(resolve("text[name=草稿]", option), .matched(19))
    }

    func testSelectorReportsAmbiguousMatchesInsteadOfGuessing() {
        let first = candidate(index: 21, role: "AXStaticText", names: ["草稿"], parentIndex: 16)
        let second = candidate(index: 44, role: "AXStaticText", names: ["草稿"], parentIndex: 30)

        guard case let .ambiguous(message) = resolve("text[name=草稿]", [first, second]) else {
            return XCTFail("two unrelated matches must be reported as ambiguous")
        }

        XCTAssertTrue(message.contains("matched 2 elements"), message)
        XCTAssertTrue(message.contains("21"), message)
        XCTAssertTrue(message.contains("44"), message)
    }

    func testSelectorReportsNotFoundWithTheClosestCandidates() {
        let fields: [ElementSelectorCandidate] = [
            candidate(index: 64, role: "AXTextArea", names: ["用途"]),
            candidate(index: 70, role: "AXTextArea", names: ["交付目标 1"]),
        ]

        guard case let .notFound(message) = resolve("textbox[name=生命周期]", fields) else {
            return XCTFail("a missing name must be reported as not found")
        }

        XCTAssertTrue(message.contains("matched no element"), message)
        XCTAssertTrue(message.contains("用途"), message)
        XCTAssertTrue(message.contains("交付目标 1"), message)
        XCTAssertTrue(message.contains("element_index"), message)
    }

    func testSelectorReportsNotFoundWhenNoElementHasTheRequestedRole() {
        let fields: [ElementSelectorCandidate] = [candidate(index: 64, role: "AXTextArea", names: ["用途"])]

        guard case let .notFound(message) = resolve("combobox[name=类型]", fields) else {
            return XCTFail("a missing role must be reported as not found")
        }

        XCTAssertTrue(message.contains("exposes no combobox element"), message)
    }

    func testSelectorWithoutRoleSearchesEveryRole() {
        let button = candidate(index: 9, role: "AXButton", names: ["检查变更"])
        XCTAssertEqual(resolve("[name=检查变更]", [button]), .matched(9))
    }

    // MARK: - Argument wiring

    func testClickRejectsElementIndexAndSelectorTogether() {
        let service = ComputerUseService()
        XCTAssertThrowsError(
            try service.click(
                app: "Finder",
                elementIndex: "3",
                selector: "button[name=检查变更]",
                x: nil,
                y: nil,
                clickCount: 1,
                mouseButton: "left"
            )
        ) { error in
            XCTAssertEqual(
                (error as? ComputerUseError)?.errorDescription,
                "invalidArguments(\"click accepts either element_index or selector, not both\")"
            )
        }
    }

    func testSetValueRequiresAnElementIndexOrASelector() {
        XCTAssertThrowsError(
            try ComputerUseToolDispatcher().callTool(
                name: "set_value",
                arguments: ["app": "Finder", "value": "draft"]
            )
        ) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, "Missing required argument: element_index or selector")
        }
    }

    func testSetValueRejectsElementIndexAndSelectorTogether() {
        // Argument validation runs before any accessibility work, so this stays
        // a pure unit test.
        XCTAssertThrowsError(
            try ComputerUseService().setValue(
                app: "Finder",
                elementIndex: "3",
                selector: "textbox[name=用途]",
                value: "draft"
            )
        ) { error in
            XCTAssertEqual(
                (error as? ComputerUseError)?.errorDescription,
                "invalidArguments(\"set_value accepts either element_index or selector, not both\")"
            )
        }
    }

    // MARK: - Helpers

    private func candidate(
        index: Int,
        role: String?,
        names: [String],
        roleText: String? = nil,
        parentIndex: Int? = nil
    ) -> ElementSelectorCandidate {
        ElementSelectorCandidate(index: index, role: role, roleText: roleText, names: names, parentIndex: parentIndex)
    }

    private func resolve(_ raw: String, _ candidates: [ElementSelectorCandidate]) -> ElementSelectorResolution {
        do {
            return resolveElementSelector(try ElementSelector.parse(raw), candidates: candidates)
        } catch {
            return .notFound("invalid selector: \(error)")
        }
    }
}
