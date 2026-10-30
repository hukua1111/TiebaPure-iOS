import XCTest
@testable import TiebaPure

/// Covers the two caches that make a row scrolling back into view cheap:
/// paragraph heights are shared between views, and the text views themselves
/// are recycled.
final class InlineTextReuseTests: XCTestCase {
    @MainActor
    override func setUp() {
        super.setUp()
        InlineContentTextMeasurementCache.drain()
        InlineContentTextViewPool.drain()
    }

    @MainActor
    override func tearDown() {
        InlineContentTextMeasurementCache.drain()
        InlineContentTextViewPool.drain()
        super.tearDown()
    }

    private func paragraph(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .callout)]
        )
    }

    @MainActor
    func testHeightMeasuredOnceIsReusedByAnotherView() {
        let text = paragraph("回到这一行时不应该重新排版的合成回复内容。")
        let first = InlineContentTextView()
        let firstSize = first.fittingSize(
            width: 320,
            attributedText: text,
            maximumNumberOfLines: 0,
            lineBreakMode: .byWordWrapping
        )
        XCTAssertGreaterThan(firstSize.height, 0)
        XCTAssertEqual(InlineContentTextMeasurementCache.cachedHeightCount, 1)

        // A different view is what scrolling back actually produces.
        let second = InlineContentTextView()
        let secondSize = second.fittingSize(
            width: 320,
            attributedText: paragraph("回到这一行时不应该重新排版的合成回复内容。"),
            maximumNumberOfLines: 0,
            lineBreakMode: .byWordWrapping
        )

        XCTAssertEqual(secondSize, firstSize)
        XCTAssertEqual(
            InlineContentTextMeasurementCache.cachedHeightCount,
            1,
            "同一段文字在同一宽度下只应测量一次"
        )
        // The cached height must not skip applying the run: the view still has
        // to be able to draw it.
        XCTAssertEqual(second.textStorage.string, text.string)
    }

    @MainActor
    func testWidthChangeIsMeasuredSeparately() {
        let text = paragraph("换宽度必须重新测量。")
        let view = InlineContentTextView()
        let narrow = view.fittingSize(
            width: 200,
            attributedText: text,
            maximumNumberOfLines: 0,
            lineBreakMode: .byWordWrapping
        )
        let wide = view.fittingSize(
            width: 400,
            attributedText: text,
            maximumNumberOfLines: 0,
            lineBreakMode: .byWordWrapping
        )

        XCTAssertEqual(InlineContentTextMeasurementCache.cachedHeightCount, 2)
        XCTAssertGreaterThanOrEqual(narrow.height, wide.height)
    }

    @MainActor
    func testLayoutPreservesUIKitOffsetWhileTextSelectionIsActive() {
        let text = paragraph(String(repeating: "选择句柄调整可视区域时不能被布局拉回原点。", count: 12))
        let view = InlineContentTextView()
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 44)
        view.isSelectable = true
        view.allowsTextSelection = true
        view.apply(
            attributedText: text,
            maximumNumberOfLines: 0,
            lineBreakMode: .byWordWrapping
        )
        view.layoutIfNeeded()
        view.selectedRange = NSRange(location: 4, length: 8)
        view.setContentOffset(CGPoint(x: 0, y: 24), animated: false)
        XCTAssertEqual(view.contentOffset.y, 24, accuracy: 0.01)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        XCTAssertEqual(
            view.contentOffset.y,
            24,
            accuracy: 0.01,
            "UIKit 为选区句柄设置的偏移不能在同一布局周期内被强制归零"
        )
    }

    @MainActor
    func testMeasurementCacheStaysBounded() {
        for index in 0..<(InlineContentTextMeasurementCache.capacity + 32) {
            InlineContentTextMeasurementCache.store(
                height: CGFloat(index),
                for: InlineContentTextMeasurementCache.Key(
                    attributedText: paragraph("回复\(index)"),
                    width: 320,
                    maximumNumberOfLines: 0,
                    lineBreakMode: NSLineBreakMode.byWordWrapping.rawValue,
                    displayScale: 3,
                    contentSizeCategory: UIContentSizeCategory.large.rawValue,
                    legibilityWeight: UILegibilityWeight.regular.rawValue
                )
            )
        }

        XCTAssertLessThanOrEqual(
            InlineContentTextMeasurementCache.cachedHeightCount,
            InlineContentTextMeasurementCache.capacity
        )
        XCTAssertGreaterThan(InlineContentTextMeasurementCache.cachedHeightCount, 0)
    }

    @MainActor
    func testDetachedViewIsRecycledBlankAndReused() async {
        let view = InlineContentTextView()
        view.accessibilityIdentifier = "thread-reply-text"
        view.allowsTextSelection = true
        view.apply(
            attributedText: paragraph("上一行回复"),
            renderID: 1,
            maximumNumberOfLines: 2,
            lineBreakMode: .byTruncatingTail
        )
        view.selectedRange = NSRange(location: 1, length: 3)

        InlineContentTextViewPool.recycle(view)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(InlineContentTextViewPool.pooledViewCount, 1)

        let reused = InlineContentTextViewPool.dequeue()
        XCTAssertTrue(reused === view, "回收的文本视图应被下一行复用")
        XCTAssertEqual(reused.textStorage.string, "")
        XCTAssertNil(reused.accessibilityIdentifier)
        XCTAssertFalse(reused.allowsTextSelection)
        XCTAssertEqual(reused.selectedRange, NSRange(location: 0, length: 0))
        XCTAssertEqual(reused.textContainer.maximumNumberOfLines, 0)

        // A fresh coordinator restarts render IDs at 1, so a recycled view must
        // not mistake the next row's first run for one it already applied.
        reused.apply(
            attributedText: paragraph("下一行回复"),
            renderID: 1,
            maximumNumberOfLines: 0,
            lineBreakMode: .byWordWrapping
        )
        XCTAssertEqual(reused.textStorage.string, "下一行回复")
    }

    @MainActor
    func testViewStillInAHierarchyIsNotReclaimed() async {
        let container = UIView()
        let view = InlineContentTextView()
        container.addSubview(view)

        InlineContentTextViewPool.recycle(view)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(
            InlineContentTextViewPool.pooledViewCount,
            0,
            "SwiftUI 还持有的视图不能回收，否则下一行会和上一行抢同一个视图"
        )
    }

    @MainActor
    func testPoolStopsGrowingAtCapacity() async {
        for _ in 0..<(InlineContentTextViewPool.capacity + 4) {
            InlineContentTextViewPool.recycle(InlineContentTextView())
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            InlineContentTextViewPool.pooledViewCount,
            InlineContentTextViewPool.capacity
        )
    }

    // MARK: - Measurement keys must not alias mutable text

    @MainActor
    private func measurementKey(
        for text: NSAttributedString,
        width: CGFloat = 320
    ) -> InlineContentTextMeasurementCache.Key {
        let traits = UITraitCollection.current
        return InlineContentTextMeasurementCache.Key(
            attributedText: text,
            width: width,
            maximumNumberOfLines: 0,
            lineBreakMode: NSLineBreakMode.byWordWrapping.rawValue,
            displayScale: 3,
            contentSizeCategory: traits.preferredContentSizeCategory.rawValue,
            legibilityWeight: traits.legibilityWeight.rawValue
        )
    }

    /// A dictionary key may not change its hash after insertion. `NSTextStorage`
    /// hashes its contents and is rewritten in place, so the shared cache has to
    /// copy it: aliasing a live storage crashed the app with
    /// `KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS`.
    @MainActor
    func testMeasurementKeySnapshotsMutableText() {
        let mutable = NSMutableAttributedString(attributedString: paragraph("同一段内容"))
        let key = measurementKey(for: mutable)
        let rebuilt = measurementKey(for: paragraph("同一段内容"))

        XCTAssertEqual(key, rebuilt, "快照后应与等价内容生成同一个 key")

        mutable.append(NSAttributedString(string: "追加内容"))

        XCTAssertEqual(key, rebuilt, "源文本变化不应改变已经构造好的 key")
        XCTAssertEqual(key.hashValue, rebuilt.hashValue)

        InlineContentTextMeasurementCache.store(height: 42, for: key)
        let cached = InlineContentTextMeasurementCache.height(for: rebuilt)
        XCTAssertEqual(cached ?? -1, 42, "同一内容必须命中同一条缓存")
    }

    /// The iOS 15 sizing path measures the view's own live text storage.
    @MainActor
    func testFittingSizeAcceptsALiveTextStorage() {
        let view = InlineContentTextView()
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 100)

        for text in ["第一段", "第二段完全不同的内容，用于触发容器重排", "第三段"] {
            view.textStorage.setAttributedString(paragraph(text))
            let size = view.fittingSize(
                width: 320,
                attributedText: view.textStorage,
                maximumNumberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )
            XCTAssertGreaterThan(size.height, 0)
        }

        // Rewriting the storage after a measurement must not corrupt the shared
        // dictionary: every later lookup and insert is expected to survive.
        XCTAssertLessThanOrEqual(
            InlineContentTextMeasurementCache.cachedHeightCount,
            InlineContentTextMeasurementCache.capacity
        )
    }
}
