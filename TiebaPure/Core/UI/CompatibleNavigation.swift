import SwiftUI

/// Stack arithmetic used by the iOS 15 navigation shim.
///
/// `NavigationStack(path:)` owns its path and pops it on its own. The shim has
/// to reproduce that contract on top of `NavigationView`, where a pop is only
/// reported through a `NavigationLink(isActive:)` binding that has no direct
/// access to the path. Keeping the array manipulation in a pure policy makes
/// the contract testable without a running navigation controller.
enum CompatibleNavigationPathPolicy {
    /// Truncates the path so that `depth` becomes the new top of the stack.
    /// A depth at or beyond the current count is a no-op, so a stale pop can
    /// never remove a level that another action already removed.
    static func popping<Route>(_ path: [Route], toDepth depth: Int) -> [Route] {
        guard depth >= 0, depth < path.count else { return path }
        return Array(path.prefix(depth))
    }
}

/// `NavigationStack(path:)` replacement that also works on iOS 15.
///
/// Routing itself is unchanged: the destination builder that used to be
/// registered with `.navigationDestination(for:)` inside the stack is passed in
/// here instead, because the iOS 15 fallback stack has to render each level
/// itself.
struct CompatibleNavigationStack<Route: Hashable, Root: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let root: Root
    private let destination: (Route) -> Destination

    init(
        path: Binding<[Route]>,
        @ViewBuilder root: () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        _path = path
        self.root = root()
        self.destination = destination
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) {
                root.navigationDestination(for: Route.self, destination: destination)
            }
        } else {
            CompatibleLegacyStack(path: $path, root: root, destination: destination)
        }
    }
}

/// `NavigationStack` replacement for stacks that only need a navigation
/// container and push their children with `NavigationLink`.
struct CompatibleNavigationContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

extension View {
    /// `navigationDestination(isPresented:destination:)` replacement.
    ///
    /// iOS 16 pushes through the bound stack; iOS 15 uses the pre-existing
    /// programmatic `NavigationLink` mechanism, which pushes onto the same
    /// `UINavigationController` and therefore keeps the same bar, toolbar and
    /// back-swipe behaviour.
    @ViewBuilder
    func compatibleNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if #available(iOS 16.0, *) {
            navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            background(
                CompatiblePushLink(isPresented: isPresented, destination: destination)
            )
        }
    }
}

/// Builds its content only once it is actually displayed, so a destination
/// that is never pushed never runs its body (and never starts a load).
struct CompatibleDeferredContent<Content: View>: View {
    let build: () -> Content

    var body: some View {
        build()
    }
}

private struct CompatiblePushLink<Destination: View>: View {
    @Binding var isPresented: Bool
    let destination: () -> Destination

    var body: some View {
        NavigationLink(isActive: $isPresented) {
            CompatibleDeferredContent(build: destination)
        } label: {
            EmptyView()
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// iOS 15 implementation of a value-driven stack.
///
/// Each level renders one element of the path and owns a zero-sized
/// `NavigationLink` that pushes the next level while the path is deeper than
/// the level itself. Popping that link (bar button or edge swipe) writes the
/// truncation back to the binding, which is what `NavigationStack` does on its
/// own on iOS 16.
private struct CompatibleLegacyStack<Route: Hashable, Root: View, Destination: View>: View {
    @Binding var path: [Route]
    let root: Root
    let destination: (Route) -> Destination

    var body: some View {
        NavigationView {
            CompatibleLegacyStackLevel(
                path: $path,
                depth: 0,
                root: root,
                destination: destination
            )
        }
        .navigationViewStyle(.stack)
    }
}

private struct CompatibleLegacyStackLevel<Route: Hashable, Root: View, Destination: View>: View {
    @Binding var path: [Route]
    let depth: Int
    let root: Root
    let destination: (Route) -> Destination

    var body: some View {
        displayedContent
            .background(pushLink)
    }

    @ViewBuilder
    private var displayedContent: some View {
        if depth == 0 {
            root
        } else if path.indices.contains(depth - 1) {
            destination(path[depth - 1])
        } else {
            EmptyView()
        }
    }

    private var pushLink: some View {
        NavigationLink(isActive: isActive) {
            // Type-erased so the recursive level type stops expanding at
            // compile time. The value is built lazily: the next level's body
            // only runs when it is actually pushed.
            AnyView(
                CompatibleLegacyStackLevel(
                    path: $path,
                    depth: depth + 1,
                    root: root,
                    destination: destination
                )
            )
        } label: {
            EmptyView()
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var isActive: Binding<Bool> {
        Binding(
            get: { path.count > depth },
            set: { newValue in
                guard newValue == false else { return }
                let updated = CompatibleNavigationPathPolicy.popping(path, toDepth: depth)
                guard updated.count != path.count else { return }
                path = updated
            }
        )
    }
}
