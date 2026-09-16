import XCTest
@testable import OpenComputerUseKit

final class PopupSnapshotTests: XCTestCase {
    // MARK: - Overlay classification

    func testTransientPopupSubtreeCoversNativeOverlaysAndFloatingWindows() {
        XCTAssertTrue(isTransientPopupSubtree(role: "AXPopover", subrole: nil))
        XCTAssertTrue(isTransientPopupSubtree(role: "AXSheet", subrole: nil))
        XCTAssertTrue(isTransientPopupSubtree(role: "AXMenu", subrole: nil))
        XCTAssertTrue(isTransientPopupSubtree(role: "AXListBox", subrole: nil))
        XCTAssertTrue(isTransientPopupSubtree(role: "AXWindow", subrole: "AXFloatingWindow"))
        XCTAssertTrue(isTransientPopupSubtree(role: "AXWindow", subrole: "AXDialog"))

        XCTAssertFalse(isTransientPopupSubtree(role: "AXWindow", subrole: "AXStandardWindow"))
        XCTAssertFalse(isTransientPopupSubtree(role: "AXButton", subrole: nil))
        XCTAssertFalse(isTransientPopupSubtree(role: nil, subrole: nil))
        XCTAssertFalse(isTransientPopupSubtree(role: "AXWindow", subrole: nil))
    }

    // MARK: - Subtree selection

    func testOverlayInItsOwnSubtreeIsAppendedNextToTheWindow() {
        let selection = transientPopupSubtreeSelection([
            PopupSubtreeDescriptor(role: "AXWindow", subrole: "AXStandardWindow", title: "Console", isPrimaryWindow: true),
            PopupSubtreeDescriptor(role: "AXPopover", subrole: nil, title: "选项", isPrimaryWindow: false),
        ])

        XCTAssertEqual(selection, [1])
    }

    func testOverlayWindowAppendsTheBackgroundWindowsItOpenedOver() {
        let selection = transientPopupSubtreeSelection([
            PopupSubtreeDescriptor(role: "AXWindow", subrole: "AXDialog", title: "", isPrimaryWindow: true),
            PopupSubtreeDescriptor(role: "AXWindow", subrole: "AXStandardWindow", title: "Console", isPrimaryWindow: false),
        ])

        XCTAssertEqual(selection, [1])
    }

    func testNoOpenOverlaySelectsNothingSoTheSnapshotStaysUnchanged() {
        let selection = transientPopupSubtreeSelection([
            PopupSubtreeDescriptor(role: "AXWindow", subrole: "AXStandardWindow", title: "Console", isPrimaryWindow: true),
            PopupSubtreeDescriptor(role: "AXWindow", subrole: "AXStandardWindow", title: "Second", isPrimaryWindow: false),
            PopupSubtreeDescriptor(role: "AXGroup", subrole: nil, title: nil, isPrimaryWindow: false),
        ])

        XCTAssertTrue(selection.isEmpty)
    }

    // MARK: - Section assembly

    func testPopupSectionKeepsTheWindowContentAndAddsTheOptions() {
        let primary = [
            "0 标准窗口 管理台",
            "\t15 HTML 内容 管理台, URL: http://127.0.0.1:8790/#/resources",
            "\t\t59 文本栏 (settable, string) 资源名称 Value: workspace-a",
        ]
        let popup = [
            "39 列表框 (settable, string)",
            "\t40 文本 (selected) 草稿",
            "\t41 文本 启用",
        ]

        let lines = appendingTransientPopupSection(primary: primary, popup: popup, note: nil)

        XCTAssertEqual(Array(lines.prefix(primary.count)), primary)
        XCTAssertEqual(lines[primary.count], "--- popup ---")
        XCTAssertEqual(Array(lines.suffix(popup.count)), popup)
        // One read now carries both the form field and the popup options.
        XCTAssertTrue(lines.contains { $0.contains("资源名称") })
        XCTAssertTrue(lines.contains { $0.contains("草稿") })
    }

    func testPopupSectionWithoutOverlayOrNoteReturnsThePrimaryLinesUntouched() {
        let primary = ["0 标准窗口 管理台", "\t1 按钮 检查变更"]
        XCTAssertEqual(appendingTransientPopupSection(primary: primary, popup: [], note: nil), primary)
    }

    func testPopupNoteIsAppendedWithoutAnyOverlaySubtree() {
        let primary = ["15 HTML 内容 管理台"]
        let lines = appendingTransientPopupSection(primary: primary, popup: [], note: "--- popup note ---")

        XCTAssertEqual(lines.first, "15 HTML 内容 管理台")
        XCTAssertEqual(lines.last, "--- popup note ---")
    }

    // MARK: - Collapsed web area (the observed Chromium + Radix shape)

    func testCollapsedWebAreaPopupNoteForChromiumListboxOverlay() {
        // Verbatim shape of a real acceptance snapshot while a Radix Select was
        // open: the web area exposes nothing but the listbox and its options.
        let records = chromiumPopupRecords()

        let note = collapsedWebAreaPopupNote(records: records, focusedIndex: 17)

        let unwrapped = try? XCTUnwrap(note)
        XCTAssertNotNil(unwrapped)
        XCTAssertTrue(unwrapped?.contains("--- popup note ---") == true)
        XCTAssertTrue(unwrapped?.contains("element_index") == true)
    }

    func testCollapsedWebAreaPopupNoteIsSilentWhenFocusIsOutsideThePopup() {
        let records = chromiumPopupRecords()

        XCTAssertNil(collapsedWebAreaPopupNote(records: records, focusedIndex: nil))
        XCTAssertNil(collapsedWebAreaPopupNote(records: records, focusedIndex: 39))
    }

    func testCollapsedWebAreaPopupNoteIsSilentWhenThePageStillExposesContent() {
        var records = chromiumPopupRecords()
        records[27] = ElementRecord(
            index: 27,
            identifier: nil,
            element: nil,
            localFrame: nil,
            role: "AXTextField",
            rawActions: [],
            prettyActions: [],
            title: "资源名称",
            parentIndex: 15
        )

        XCTAssertNil(collapsedWebAreaPopupNote(records: records, focusedIndex: 17))
    }

    func testCollapsedWebAreaPopupNoteIgnoresAWebAreaWithoutAPopupChild() {
        let records: [Int: ElementRecord] = [
            0: ElementRecord(index: 0, identifier: nil, element: nil, localFrame: nil, role: "AXWindow", rawActions: [], prettyActions: []),
            1: ElementRecord(index: 1, identifier: nil, element: nil, localFrame: nil, role: "AXWebArea", rawActions: [], prettyActions: [], parentIndex: 0),
            2: ElementRecord(index: 2, identifier: nil, element: nil, localFrame: nil, role: "AXStaticText", rawActions: [], prettyActions: [], title: "日志", parentIndex: 1),
        ]

        XCTAssertNil(collapsedWebAreaPopupNote(records: records, focusedIndex: 2))
    }

    /// The Chromium tree from the acceptance run that motivated this work: the
    /// window chrome stays, the web area collapses to the open listbox, and
    /// keyboard focus sits inside the listbox.
    private func chromiumPopupRecords() -> [Int: ElementRecord] {
        let chain: [(Int, String, Int?)] = [
            (0, "AXWindow", nil),
            (1, "AXGroup", 0),
            (3, "AXToolbar", 1),
            (15, "AXWebArea", 1),
            (16, "AXListBox", 15),
            (17, "AXStaticText", 16),
            (18, "AXStaticText", 17),
            (19, "AXStaticText", 16),
            (20, "AXStaticText", 19),
            (39, "AXComboBox", 1),
        ]

        var records: [Int: ElementRecord] = [:]
        for (index, role, parentIndex) in chain {
            records[index] = ElementRecord(
                index: index,
                identifier: nil,
                element: nil,
                localFrame: nil,
                role: role,
                rawActions: [],
                prettyActions: [],
                title: role == "AXStaticText" ? "请选择" : nil,
                roleText: role,
                parentIndex: parentIndex
            )
        }

        return records
    }
}
