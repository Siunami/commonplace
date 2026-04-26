import MarkdownUI
import SwiftUI

extension Theme {
    /// MarkdownUI theme tuned to the existing detail-view body voice:
    /// 18pt serif, primary @ 0.92, generous line spacing. Headings step
    /// up in size; code uses monospaced + subtle fill; blockquotes get
    /// a thin neutral left bar (mirrors the inline-notes treatment in
    /// `MaterialListRow`); links accent-tinted + underlined.
    ///
    /// Plain captures with no markdown tokens render visually identical
    /// to the previous `Text(...)` site — the paragraph defaults match.
    static let commonplace: Theme = Theme()
        .text {
            FontFamily(.system(.serif))
            FontSize(18)
            ForegroundColor(.primary.opacity(0.92))
        }
        .paragraph { config in
            config.label
                .lineSpacing(4)
                .padding(.bottom, 4)
        }
        .heading1 { config in
            config.label
                .markdownTextStyle {
                    FontFamily(.system(.serif))
                    FontWeight(.semibold)
                    FontSize(28)
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
        }
        .heading2 { config in
            config.label
                .markdownTextStyle {
                    FontFamily(.system(.serif))
                    FontWeight(.semibold)
                    FontSize(22)
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
        }
        .heading3 { config in
            config.label
                .markdownTextStyle {
                    FontFamily(.system(.serif))
                    FontWeight(.medium)
                    FontSize(19)
                }
                .padding(.top, 8)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.92))
            BackgroundColor(.primary.opacity(0.06))
        }
        .codeBlock { config in
            ScrollView(.horizontal, showsIndicators: false) {
                config.label
                    .padding(10)
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(13)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .blockquote { config in
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1)
                config.label
                    .markdownTextStyle { FontStyle(.italic) }
            }
        }
        .link {
            ForegroundColor(.accentColor)
            UnderlineStyle(.single)
        }

    /// Marginalia variant of `commonplace` — used for user notes attached
    /// to a captured highlight. Same markdown features (so the user can
    /// write structured reflections), but visually distinct from the
    /// primary content: smaller, italic serif, slightly de-emphasised
    /// foreground. Reads as commentary alongside the source rather than
    /// competing with it.
    static let commonplaceMarginalia: Theme = Theme()
        .text {
            FontFamily(.system(.serif))
            FontStyle(.italic)
            FontSize(15)
            ForegroundColor(.primary.opacity(0.78))
        }
        .paragraph { config in
            config.label
                .lineSpacing(3)
                .padding(.bottom, 2)
        }
        .heading1 { config in
            config.label.markdownTextStyle {
                FontFamily(.system(.serif))
                FontWeight(.semibold)
                FontStyle(.italic)
                FontSize(20)
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .heading2 { config in
            config.label.markdownTextStyle {
                FontFamily(.system(.serif))
                FontWeight(.semibold)
                FontStyle(.italic)
                FontSize(17)
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .heading3 { config in
            config.label.markdownTextStyle {
                FontFamily(.system(.serif))
                FontWeight(.medium)
                FontStyle(.italic)
                FontSize(15)
            }
            .padding(.top, 4)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontStyle(.normal)
            FontSize(.em(0.92))
            BackgroundColor(.primary.opacity(0.06))
        }
        .codeBlock { config in
            ScrollView(.horizontal, showsIndicators: false) {
                config.label
                    .padding(8)
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontStyle(.normal)
                        FontSize(12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .blockquote { config in
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1)
                config.label
            }
        }
        .link {
            ForegroundColor(.accentColor)
            UnderlineStyle(.single)
        }
}
