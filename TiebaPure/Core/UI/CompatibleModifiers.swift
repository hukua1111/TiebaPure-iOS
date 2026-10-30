import SwiftUI
import UIKit

// MARK: - Tab bar

extension View {
    /// `toolbar(_:for: .tabBar)` replacement.
    ///
    /// iOS 16 lets a pushed page hide the tab bar through the toolbar API. That
    /// API does not exist before iOS 16; the pre-16 system behaviour is to keep
    /// the tab bar visible for every page of the tab, so the call is simply
    /// omitted and the default iOS 15 presentation is preserved.
    @ViewBuilder
    func compatibleTabBarVisibility(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            toolbar(visibility, for: .tabBar)
        } else {
            self
        }
    }
}

// MARK: - Scroll view styling

extension View {
    /// `scrollIndicators(.hidden)` replacement.
    @ViewBuilder
    func compatibleHiddenScrollIndicators() -> some View {
        if #available(iOS 16.0, *) {
            scrollIndicators(.hidden)
        } else {
            background(CompatibleScrollViewTuner(configuration: .init(hidesIndicators: true)))
        }
    }

    /// `scrollContentBackground(.hidden)` replacement.
    @ViewBuilder
    func compatibleHiddenScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            background(CompatibleScrollViewTuner(configuration: .init(clearsBackground: true)))
        }
    }

    /// `scrollDismissesKeyboard(.interactively)` replacement.
    @ViewBuilder
    func compatibleInteractiveKeyboardDismissal() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            background(
                CompatibleScrollViewTuner(configuration: .init(keyboardDismissMode: .interactive))
            )
        }
    }

    /// `scrollBounceBehavior(.always, axes: .vertical)` replacement.
    @ViewBuilder
    func compatibleAlwaysVerticalBounce() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.always, axes: .vertical)
        } else {
            background(
                CompatibleScrollViewTuner(configuration: .init(alwaysBounceVertical: true))
            )
        }
    }
}

/// Applies the iOS 16 scroll modifiers to the platform scroll view that backs
/// the hierarchy. The attachment view is invisible and non-interactive, and the
/// lookup fails silently, so a hierarchy this cannot resolve keeps the iOS 15
/// default instead of trapping.
private struct CompatibleScrollViewTuner: UIViewRepresentable {
    struct Configuration: Equatable {
        var hidesIndicators = false
        var clearsBackground = false
        var keyboardDismissMode: UIScrollView.KeyboardDismissMode?
        var alwaysBounceVertical = false
    }

    let configuration: Configuration

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        view.onHierarchyChange = { [weak coordinator = context.coordinator] attachment in
            coordinator?.scheduleConfiguration(of: attachment)
        }
        context.coordinator.scheduleConfiguration(of: view)
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.configuration = configuration
        context.coordinator.scheduleConfiguration(of: uiView)
    }

    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) {
        uiView.onHierarchyChange = nil
    }

    final class AttachmentView: UIView {
        var onHierarchyChange: ((AttachmentView) -> Void)?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onHierarchyChange?(self)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onHierarchyChange?(self)
        }
    }

    final class Coordinator {
        var configuration: Configuration

        init(configuration: Configuration) {
            self.configuration = configuration
        }

        func scheduleConfiguration(of attachment: AttachmentView) {
            DispatchQueue.main.async { [weak self, weak attachment] in
                guard let self, let attachment else { return }
                guard let scrollView = Self.enclosingScrollView(startingAt: attachment) else {
                    return
                }
                self.applyConfiguration(to: scrollView)
            }
        }

        private func applyConfiguration(to scrollView: UIScrollView) {
            if configuration.hidesIndicators {
                scrollView.showsVerticalScrollIndicator = false
                scrollView.showsHorizontalScrollIndicator = false
            }
            if configuration.clearsBackground {
                scrollView.backgroundColor = .clear
                if let tableView = scrollView as? UITableView {
                    tableView.backgroundView = nil
                }
                if let textView = scrollView as? UITextView {
                    textView.backgroundColor = .clear
                }
            }
            if let keyboardDismissMode = configuration.keyboardDismissMode {
                scrollView.keyboardDismissMode = keyboardDismissMode
            }
            if configuration.alwaysBounceVertical {
                scrollView.alwaysBounceVertical = true
            }
        }

        private static func enclosingScrollView(startingAt attachment: UIView) -> UIScrollView? {
            var current = attachment.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                current = candidate.superview
            }

            // A modifier applied above a scroll view can attach behind a
            // wrapper instead of inside the scroll view. Fall back to the
            // smallest visible scroll view that covers the attachment.
            guard let window = attachment.window else { return nil }
            let attachmentFrame = attachment.convert(attachment.bounds, to: window)
            guard attachmentFrame.isEmpty == false else { return nil }

            var pending: [UIView] = window.subviews
            var bestMatch: UIScrollView?
            while let candidate = pending.popLast() {
                if let scrollView = candidate as? UIScrollView,
                   scrollView.isHidden == false,
                   scrollView.window === window {
                    let frame = scrollView.convert(scrollView.bounds, to: window)
                    if frame.contains(CGPoint(x: attachmentFrame.midX, y: attachmentFrame.midY)) {
                        if let current = bestMatch {
                            let currentArea = current.bounds.width * current.bounds.height
                            let candidateArea = scrollView.bounds.width * scrollView.bounds.height
                            if candidateArea < currentArea {
                                bestMatch = scrollView
                            }
                        } else {
                            bestMatch = scrollView
                        }
                    }
                }
                pending.append(contentsOf: candidate.subviews)
            }
            return bestMatch
        }
    }
}

// MARK: - Adaptive layout

/// `ViewThatFits` replacement for the "wide layout, stacked fallback" pairs the
/// reader screens use.
///
/// iOS 16 negotiates between the two layouts and picks the first one that fits.
/// iOS 15 has no such negotiation, so the preferred (horizontal) layout is used
/// as-is, except at accessibility text sizes where the compact variant is what
/// the negotiation would end up choosing anyway.
struct CompatibleViewThatFits<Preferred: View, Fallback: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let axis: Axis.Set
    private let preferred: Preferred
    private let fallback: Fallback

    init(
        in axis: Axis.Set = .horizontal,
        @ViewBuilder preferred: () -> Preferred,
        @ViewBuilder fallback: () -> Fallback
    ) {
        self.axis = axis
        self.preferred = preferred()
        self.fallback = fallback()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: axis) {
                preferred
                fallback
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            fallback
        } else {
            preferred
        }
    }
}

// MARK: - Labeled content

/// `LabeledContent` replacement.
struct CompatibleLabeledContent<Content: View>: View {
    private let title: LocalizedStringKey
    private let value: String?
    private let content: Content

    init(_ title: LocalizedStringKey, value: String) where Content == EmptyView {
        self.title = title
        self.value = value
        self.content = EmptyView()
    }

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = nil
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            if let value {
                LabeledContent(title, value: value)
            } else {
                LabeledContent { content } label: { Text(title) }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: TiebaPureTheme.Spacing.sm) {
                Text(title)
                Spacer(minLength: TiebaPureTheme.Spacing.sm)
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } else {
                    content
                }
            }
        }
    }
}

// MARK: - Share

/// `ShareLink` replacement. iOS 15 shares through the system activity
/// controller, which is what `ShareLink` presents on iOS 16 as well.
struct CompatibleShareLink<Label: View>: View {
    private let item: URL
    private let label: Label

    init(item: URL, @ViewBuilder label: () -> Label) {
        self.item = item
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: item) { label }
        } else {
            Button {
                Task { @MainActor in
                    CompatibleShareSheet.present(item)
                }
            } label: {
                label
            }
        }
    }
}

@MainActor
enum CompatibleShareSheet {
    static func present(_ item: URL) {
        guard let controller = topViewController() else { return }
        let activity = UIActivityViewController(
            activityItems: [item],
            applicationActivities: nil
        )
        if let popover = activity.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(
                x: controller.view.bounds.midX,
                y: controller.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        controller.present(activity, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }

        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

// MARK: - Navigation link

/// `NavigationLink` replacement for the `destination:`/`label:` builder pair,
/// which only accepts a destination closure from iOS 16 on.
struct CompatibleNavigationLink<Destination: View, Label: View>: View {
    private let destination: Destination
    private let label: Label

    init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.destination = destination()
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationLink { destination } label: { label }
        } else {
            NavigationLink(destination: destination) { label }
        }
    }
}

// MARK: - Typography

extension View {
    /// `fontDesign(.monospaced)` replacement.
    ///
    /// The monospaced design keeps a changing label from reflowing as the
    /// loading text changes width. iOS 15 has no design modifier that preserves
    /// the inherited size, so the declaration is dropped there and the text
    /// keeps the design inherited from its context.
    @ViewBuilder
    func compatibleMonospacedFontDesign() -> some View {
        // `fontDesign` is iOS 16.1, not 16.0.
        if #available(iOS 16.1, *) {
            fontDesign(.monospaced)
        } else {
            self
        }
    }
}

// MARK: - Foundation

extension URL {
    /// `appending(path:)` replacement, which is iOS 16 only.
    func compatibleAppending(path: String) -> URL {
        if #available(iOS 16.0, *) {
            return appending(path: path)
        }
        return appendingPathComponent(path)
    }

    /// `appending(queryItems:)` replacement, which is iOS 16 only.
    func compatibleAppending(queryItems: [URLQueryItem]) -> URL {
        if #available(iOS 16.0, *) {
            return appending(queryItems: queryItems)
        }
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: queryItems)
        components.queryItems = items
        return components.url ?? self
    }

    /// `appending(path:directoryHint:)` replacement, which is iOS 16 only.
    func compatibleAppending(path: String, isDirectory: Bool) -> URL {
        if #available(iOS 16.0, *) {
            return appending(
                path: path,
                directoryHint: isDirectory ? .isDirectory : .notDirectory
            )
        }
        return appendingPathComponent(path, isDirectory: isDirectory)
    }
}

extension NSLocking {
    /// `withLock` replacement: the standard library version is iOS 16 only.
    func withCompatibleLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// `Task.sleep(for: Duration)` is iOS 16 only and `Duration` itself carries the
/// same availability, so callers keep their interval as a `TimeInterval` and
/// convert it here.
enum CompatibleTaskDelay {
    static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        guard interval.isFinite, interval > 0 else { return 0 }
        return UInt64((interval * 1_000_000_000).rounded())
    }
}
