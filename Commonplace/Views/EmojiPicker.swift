import SwiftUI

// MARK: - Emoji Picker View

struct EmojiPickerView: View {
    let currentEmoji: String?
    let onSelect: (String) -> Void
    let onRemove: () -> Void

    @State private var searchText = ""
    @State private var selectedCategory = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Search emoji...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))

            Divider()

            if searchText.isEmpty {
                // Category tabs
                HStack(spacing: 0) {
                    ForEach(Array(EmojiData.categories.enumerated()), id: \.offset) { index, category in
                        Button(action: { selectedCategory = index }) {
                            Text(category.icon)
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(selectedCategory == index ? Color.primary.opacity(0.08) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help(category.name)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

                Divider()
            }

            // Emoji grid
            ScrollViewReader { proxy in
                ScrollView {
                    if searchText.isEmpty {
                        categoryGrid(proxy: proxy)
                    } else {
                        searchResultsGrid
                    }
                }
                .onChange(of: selectedCategory) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo("cat-\(newValue)", anchor: .top)
                    }
                }
            }

            // Remove button
            if currentEmoji != nil {
                Divider()
                Button(action: onRemove) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Remove icon")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280, height: 320)
    }

    // MARK: - Category Grid

    private func categoryGrid(proxy: ScrollViewProxy) -> some View {
        let columns = Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8)
        return LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
            ForEach(Array(EmojiData.categories.enumerated()), id: \.offset) { index, category in
                Section {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(category.emojis, id: \.self) { emoji in
                            emojiButton(emoji)
                        }
                    }
                } header: {
                    Text(category.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .id("cat-\(index)")
                }
            }
        }
        .padding(8)
    }

    // MARK: - Search Results

    private var searchResultsGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8)
        let results = EmojiData.search(searchText)
        return Group {
            if results.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No emoji found")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(results, id: \.self) { emoji in
                        emojiButton(emoji)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Emoji Button

    private func emojiButton(_ emoji: String) -> some View {
        Button(action: { onSelect(emoji) }) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(currentEmoji == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Emoji Data

enum EmojiData {
    struct Category {
        let name: String
        let icon: String
        let emojis: [String]
    }

    static let categories: [Category] = [
        Category(name: "Smileys & People", icon: "😀", emojis: [
            "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃",
            "😉","😊","😇","🥰","😍","🤩","😘","😗","😚","😙",
            "🥲","😋","😛","😜","🤪","😝","🤑","🤗","🤭","🫢",
            "🫣","🤫","🤔","🫡","🤐","🤨","😐","😑","😶","🫥",
            "😏","😒","🙄","😬","🤥","😌","😔","😪","🤤","😴",
            "😷","🤒","🤕","🤢","🤮","🥵","🥶","🥴","😵","🤯",
            "🤠","🥳","🥸","😎","🤓","🧐","😕","🫤","😟","🙁",
            "😮","😯","😲","😳","🥺","🥹","😦","😧","😨","😰",
            "😥","😢","😭","😱","😖","😣","😞","😓","😩","😫",
            "🥱","😤","😡","😠","🤬","😈","👿","💀","☠️","💩",
            "🤡","👹","👺","👻","👽","👾","🤖","😺","😸","😹",
            "😻","😼","😽","🙀","😿","😾","🙈","🙉","🙊",
            "👋","🤚","🖐️","✋","🖖","🫱","🫲","🫳","🫴","🫷",
            "🫸","👌","🤌","🤏","✌️","🤞","🫰","🤟","🤘","🤙",
            "👈","👉","👆","🖕","👇","☝️","🫵","👍","👎","✊",
            "👊","🤛","🤜","👏","🙌","🫶","👐","🤲","🤝","🙏",
        ]),
        Category(name: "Animals & Nature", icon: "🐻", emojis: [
            "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐻‍❄️","🐨",
            "🐯","🦁","🐮","🐷","🐸","🐵","🙈","🙉","🙊","🐒",
            "🐔","🐧","🐦","🐤","🐣","🐥","🦆","🦅","🦉","🦇",
            "🐺","🐗","🐴","🦄","🐝","🪱","🐛","🦋","🐌","🐞",
            "🐜","🪰","🪲","🪳","🦟","🦗","🕷️","🦂","🐢","🐍",
            "🦎","🦖","🦕","🐙","🦑","🦐","🦞","🦀","🪼","🐡",
            "🐠","🐟","🐬","🐳","🐋","🦈","🪸","🐊","🐅","🐆",
            "🦓","🫏","🦍","🦧","🐘","🦛","🦏","🐪","🐫","🦒",
            "🦘","🦬","🐃","🐂","🐄","🐎","🐖","🐏","🐑","🦙",
            "🐐","🦌","🐕","🐩","🦮","🐕‍🦺","🐈","🐈‍⬛","🪶","🐓",
            "🦃","🦤","🦚","🦜","🦢","🪿","🦩","🕊️","🐇","🦝",
            "🦨","🦡","🦫","🦦","🦥","🐁","🐀","🐿️","🦔",
            "🌵","🎄","🌲","🌳","🌴","🪵","🌱","🌿","☘️","🍀",
            "🪴","🎋","🎍","🍃","🍂","🍁","🌾","🪻","🌺","🌸",
            "🌼","🌻","🌞","🌝","🌛","🌜","🌚","🌕","🌖","🌗",
            "🌘","🌑","🌒","🌓","🌔","🌙","🌎","🌍","🌏","🪐",
            "💫","⭐","🌟","✨","⚡","☄️","💥","🔥","🌪️","🌈",
            "☀️","🌤️","⛅","🌥️","☁️","🌦️","🌧️","⛈️","🌩️","🌨️",
            "❄️","☃️","⛄","🌬️","💨","💧","💦","🫧","☔","☂️",
            "🌊","🌫️",
        ]),
        Category(name: "Food & Drink", icon: "🍔", emojis: [
            "🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐",
            "🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🍆","🥑",
            "🫛","🥦","🥬","🥒","🌶️","🫑","🌽","🥕","🫒","🧄",
            "🧅","🥔","🍠","🫘","🥜","🌰","🫚","🫛",
            "🍞","🥐","🥖","🫓","🥨","🥯","🥞","🧇","🧀","🍖",
            "🍗","🥩","🥓","🍔","🍟","🍕","🌭","🥪","🌮","🌯",
            "🫔","🥙","🧆","🥚","🍳","🥘","🍲","🫕","🥣","🥗",
            "🍿","🧈","🧂","🥫","🍱","🍘","🍙","🍚","🍛","🍜",
            "🍝","🍠","🍢","🍣","🍤","🍥","🥮","🍡","🥟","🥠",
            "🥡","🦀","🦞","🦐","🦑","🦪",
            "🍦","🍧","🍨","🍩","🍪","🎂","🍰","🧁","🥧","🍫",
            "🍬","🍭","🍮","🍯",
            "🍼","🥛","☕","🫖","🍵","🍶","🍾","🍷","🍸","🍹",
            "🍺","🍻","🥂","🥃","🫗","🥤","🧋","🧃","🧉","🧊",
        ]),
        Category(name: "Activities", icon: "⚽", emojis: [
            "⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱",
            "🪀","🏓","🏸","🏒","🏑","🥍","🏏","🪃","🥅","⛳",
            "🪁","🏹","🎣","🤿","🥊","🥋","🎽","🛹","🛼","🛷",
            "⛸️","🥌","🎿","⛷️","🏂","🪂","🏋️","🤸","🤺","⛹️",
            "🤾","🏌️","🏇","🧘","🏄","🏊","🤽","🚣","🧗","🚵",
            "🚴","🏆","🥇","🥈","🥉","🏅","🎖️","🏵️","🎗️","🎪",
            "🤹","🎭","🩰","🎨","🎬","🎤","🎧","🎼","🎹","🥁",
            "🪘","🪇","🎷","🎺","🪗","🎸","🪕","🎻","🎲","♟️",
            "🎯","🎳","🎮","🕹️","🎰",
        ]),
        Category(name: "Travel & Places", icon: "✈️", emojis: [
            "🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐",
            "🛻","🚚","🚛","🚜","🏍️","🛵","🚲","🛴","🛺","🚔",
            "🚍","🚘","🚖","🛞","🚡","🚠","🚟","🚃","🚋","🚞",
            "🚝","🚄","🚅","🚈","🚂","🚆","🚇","🚊","🚉","✈️",
            "🛫","🛬","🛩️","💺","🛰️","🚀","🛸","🚁","🛶","⛵",
            "🚤","🛥️","🛳️","⛴️","🚢","⚓","🪝","⛽","🚧","🚦",
            "🚥","🛑","🚏","🗺️","🗿","🗽","🗼","🏰","🏯","🏟️",
            "🎡","🎢","🎠","⛲","⛱️","🏖️","🏝️","🏜️","🌋","⛰️",
            "🏔️","🗻","🏕️","⛺","🛖","🏠","🏡","🏘️","🏚️","🏗️",
            "🏭","🏢","🏬","🏣","🏤","🏥","🏦","🏨","🏪","🏫",
            "🏩","💒","🏛️","⛪","🕌","🕍","🛕","🕋","⛩️","🛤️",
            "🛣️","🗾","🎑","🏞️","🌅","🌄","🌠","🎇","🎆","🌇",
            "🌆","🏙️","🌃","🌌","🌉","🌁",
        ]),
        Category(name: "Objects", icon: "💡", emojis: [
            "⌚","📱","📲","💻","⌨️","🖥️","🖨️","🖱️","🖲️","🕹️",
            "🗜️","💽","💾","💿","📀","📼","📷","📸","📹","🎥",
            "📽️","🎞️","📞","☎️","📟","📠","📺","📻","🎙️","🎚️",
            "🎛️","🧭","⏱️","⏲️","⏰","🕰️","⌛","⏳","📡","🔋",
            "🪫","🔌","💡","🔦","🕯️","🪔","🧯","🛢️","🛒",
            "💰","💴","💵","💶","💷","🪙","💸","💳","🧾","💹",
            "✉️","📧","📨","📩","📤","📥","📦","📫","📪","📬",
            "📭","📮","🗳️","✏️","✒️","🖋️","🖊️","🖌️","🖍️","📝",
            "💼","📁","📂","🗂️","📅","📆","🗒️","🗓️","📇","📈",
            "📉","📊","📋","📌","📍","📎","🖇️","📏","📐","✂️",
            "🗃️","🗄️","🗑️","🔒","🔓","🔏","🔐","🔑","🗝️","🔨",
            "🪓","⛏️","⚒️","🛠️","🗡️","⚔️","💣","🪃","🏹","🛡️",
            "🪚","🔧","🪛","🔩","⚙️","🗜️","⚖️","🦯","🔗","⛓️",
            "🪝","🧰","🧲","🪜","⚗️","🧪","🧫","🧬","🔬","🔭",
            "📡","💉","🩸","💊","🩹","🩼","🩺","🩻",
            "🚪","🛗","🪞","🪟","🛏️","🛋️","🪑","🚽","🪠","🚿",
            "🛁","🪤","🪒","🧴","🧷","🧹","🧺","🧻","🪣","🧼",
            "🫧","🪥","🧽","🧯","🎈","🎏","🎀","🎁","🎊","🎉",
            "🎎","🎐","🎌","🏮","🪩","🪅","🧧","✉️",
            "📕","📗","📘","📙","📚","📖","🔖","🧷","🔗","📎",
        ]),
        Category(name: "Symbols", icon: "💜", emojis: [
            "❤️","🩷","🧡","💛","💚","💙","🩵","💜","🖤","🩶",
            "🤍","🤎","💔","❤️‍🔥","❤️‍🩹","❣️","💕","💞","💓","💗",
            "💖","💘","💝","💟","☮️","✝️","☪️","🕉️","☸️","✡️",
            "🔯","🪯","☯️","☦️","🛐","⛎","♈","♉","♊","♋",
            "♌","♍","♎","♏","♐","♑","♒","♓","🆔","⚛️",
            "🉐","🈶","🈚","🈸","🈺","🈷️","✴️","🆚","💮","🉑",
            "🈴","🈵","🈹","🈲","🅰️","🅱️","🆎","🆑","🅾️","🆘",
            "❌","⭕","🛑","⛔","📛","🚫","💯","💢","♨️","🚷",
            "🚯","🚳","🔞","📵","🚭","❗","❕","❓","❔","‼️",
            "⁉️","🔅","🔆","〽️","⚠️","🚸","🔱","⚜️","🔰","♻️",
            "✅","🈯","💹","❇️","✳️","❎","🌐","💠","Ⓜ️","🌀",
            "💤","🏧","🚾","♿","🅿️","🛗","🈳","🈂️","🛂","🛃",
            "🛄","🛅","🔣","ℹ️","🔤","🔡","🔠","🆖","🆗","🆙",
            "🆒","🆕","🆓","0️⃣","1️⃣","2️⃣","3️⃣","4️⃣","5️⃣","6️⃣",
            "7️⃣","8️⃣","9️⃣","🔟","🔢","#️⃣","*️⃣","⏏️","▶️","⏸️",
            "⏯️","⏹️","⏺️","⏭️","⏮️","⏩","⏪","🔀","🔁","🔂",
            "◀️","🔼","🔽","⏫","⏬","➡️","⬅️","⬆️","⬇️","↗️",
            "↘️","↙️","↖️","↕️","↔️","🔄","↪️","↩️","⤴️","⤵️",
            "🔃","🔙","🔛","🔝","🔜",
        ]),
        Category(name: "Flags", icon: "🏁", emojis: [
            "🏳️","🏴","🏁","🚩","🏳️‍🌈","🏳️‍⚧️","🏴‍☠️",
            "🇺🇸","🇬🇧","🇨🇦","🇦🇺","🇩🇪","🇫🇷","🇮🇹","🇪🇸","🇯🇵","🇰🇷",
            "🇨🇳","🇮🇳","🇧🇷","🇲🇽","🇷🇺","🇿🇦","🇳🇬","🇪🇬","🇰🇪","🇦🇷",
            "🇨🇴","🇵🇪","🇨🇱","🇻🇪","🇪🇨","🇧🇴","🇵🇾","🇺🇾","🇵🇦","🇨🇷",
            "🇬🇹","🇭🇳","🇸🇻","🇳🇮","🇨🇺","🇩🇴","🇵🇷","🇯🇲","🇹🇹","🇧🇸",
            "🇧🇧","🇭🇹","🇮🇪","🇮🇸","🇳🇴","🇸🇪","🇫🇮","🇩🇰","🇳🇱","🇧🇪",
            "🇱🇺","🇨🇭","🇦🇹","🇵🇱","🇨🇿","🇸🇰","🇭🇺","🇷🇴","🇧🇬","🇭🇷",
            "🇷🇸","🇺🇦","🇬🇷","🇹🇷","🇮🇱","🇸🇦","🇦🇪","🇶🇦","🇰🇼","🇧🇭",
            "🇴🇲","🇮🇶","🇮🇷","🇵🇰","🇧🇩","🇱🇰","🇳🇵","🇹🇭","🇻🇳","🇮🇩",
            "🇲🇾","🇸🇬","🇵🇭","🇲🇲","🇰🇭","🇱🇦","🇹🇼","🇭🇰","🇲🇴","🇲🇳",
            "🇳🇿","🇫🇯","🇵🇬","🇪🇹","🇬🇭","🇹🇿","🇺🇬","🇲🇦","🇹🇳","🇩🇿",
            "🇱🇾","🇸🇩","🇨🇲","🇨🇩","🇲🇿","🇲🇬","🇸🇳","🇨🇮",
        ]),
    ]

    /// Search emoji by Unicode character name (e.g., "cat" finds 🐱 CAT FACE).
    static func search(_ query: String) -> [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        var results: [String] = []
        for category in categories {
            for emoji in category.emojis {
                // Check Unicode scalar name
                if let scalar = emoji.unicodeScalars.first,
                   let name = scalar.properties.name?.lowercased(),
                   name.contains(q) {
                    results.append(emoji)
                }
            }
        }
        return results
    }
}
