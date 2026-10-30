import SwiftUI

struct SubpostPreviewView: View {
    let subposts: [Subpost]
    let totalCount: Int
    let threadAuthorID: Int64?
    let onOpenAll: (() -> Void)?
    let onOpenUser: ((UserSummary) -> Void)?

    init(
        subposts: [Subpost],
        totalCount: Int,
        threadAuthorID: Int64?,
        onOpenAll: (() -> Void)? = nil,
        onOpenUser: ((UserSummary) -> Void)? = nil
    ) {
        self.subposts = Array(subposts.prefix(3))
        self.totalCount = totalCount
        self.threadAuthorID = threadAuthorID
        self.onOpenAll = onOpenAll
        self.onOpenUser = onOpenUser
    }

    private var showsOpenAllRow: Bool {
        totalCount > subposts.count && onOpenAll != nil
    }

    var body: some View {
        if subposts.isEmpty == false {
            VStack(alignment: .leading, spacing: SubpostPreviewLayout.openAllTopSpacing) {
                VStack(alignment: .leading, spacing: SubpostPreviewLayout.rowSpacing) {
                    ForEach(subposts) { subpost in
                        SubpostInlineRow(
                            subpost: subpost,
                            threadAuthorID: threadAuthorID,
                            lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                            onOpenUser: onOpenUser
                        )
                    }
                }

                if showsOpenAllRow, let onOpenAll {
                    Button {
                        onOpenAll()
                    } label: {
                        HStack(spacing: 2) {
                            Text("查看全部\(totalCount)条回复")
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .font(.footnote)
                        .foregroundStyle(TiebaPureTheme.ColorToken.primaryAccent)
                        // The row is a full 44pt target rather than a 30pt label
                        // with an expanded hit shape: a hit shape that reaches
                        // outside the frame is not reliably delivered, and the
                        // label has no background, so the extra height only adds
                        // tap area around the text.
                        .frame(
                            maxWidth: .infinity,
                            minHeight: SubpostPreviewLayout.openAllRowHeight,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看全部\(totalCount)条回复")
                    .accessibilityIdentifier("thread-subpost-open-all")
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.top, ThreadReplyLayout.previewTopPadding)
            // The 44pt row already separates the text from the card's edge, so
            // the card does not also need the usual padding below it. Cards
            // without the row keep the original spacing.
            .padding(
                .bottom,
                showsOpenAllRow ? 0 : ThreadReplyLayout.previewBottomPadding
            )
            .background(
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("thread-subpost-preview")
        }
    }
}

enum SubpostPreviewLayout {
    static let rowSpacing: CGFloat = TiebaPureTheme.Spacing.xs
    static let openAllTopSpacing: CGFloat = TiebaPureTheme.Spacing.xxs
    /// The smallest comfortable tap target. The label itself is only a 13pt
    /// line, so the row is laid out at this height with the text centred.
    static let openAllRowHeight: CGFloat = 44
}

struct SubpostInlineRow: View {
    @Environment(\.readingPreferences) private var readingPreferences

    let subpost: Subpost
    let threadAuthorID: Int64?
    var lineLimit: Int = ThreadContentDisplayPolicy.detailLineLimit
    var onOpenUser: ((UserSummary) -> Void)?

    var body: some View {
        InlineContentText(
            blocks: subpost.blocks,
            style: .subpost,
            lineLimit: lineLimit,
            readerFontSize: readingPreferences.fontSize,
            readerFontFamily: readingPreferences.fontFamily,
            readerLineSpacing: readingPreferences.lineSpacing,
            prefixParts: SubpostInlinePrefix.parts(
                author: subpost.author,
                isThreadAuthor: isThreadAuthor
            ),
            allowsTextSelection: ThreadContentInteractionPolicy.allowsTextSelection(
                for: lineLimit
            ),
            accessibilityIdentifier: "thread-subpost-preview-text",
            onOpenUser: onOpenUser
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isThreadAuthor: Bool {
        guard let threadAuthorID else { return false }
        return threadAuthorID != 0 && subpost.author.id == threadAuthorID
    }
}

enum SubpostInlinePrefix {
    static func parts(author: UserSummary, isThreadAuthor: Bool) -> [InlineContentText.PrefixPart] {
        guard isThreadAuthor else {
            return [.user(author), .text(": ")]
        }
        return [
            .user(author),
            .text(" "),
            .threadAuthorBadge,
            .text(": ")
        ]
    }
}
