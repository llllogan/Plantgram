import SwiftUI

struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(EmojiCatalog.categories) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(category.title, systemImage: category.systemImage)
                                .font(.headline)
                                .padding(.horizontal, 4)

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(category.emojis, id: \.self) { emoji in
                                    Button {
                                        onSelect(emoji)
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 28))
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(emoji)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Reaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct EmojiCategory: Identifiable {
    let title: String
    let systemImage: String
    let emojis: [String]

    var id: String { title }
}

private enum EmojiCatalog {
    static let categories: [EmojiCategory] = [
        EmojiCategory(
            title: "Smileys & People",
            systemImage: "face.smiling",
            emojis: emojiStrings(
                ranges: [
                    0x1F600...0x1F64F,
                    0x1F910...0x1F92F,
                    0x1F930...0x1F939,
                    0x1F93D...0x1F93E,
                    0x1F970...0x1F97F,
                    0x1F9D0...0x1F9DD
                ],
                extras: [
                    "👋🏻", "👋🏽", "👍🏻", "👍🏽", "👏🏻", "🙏🏽", "🙌🏽",
                    "👨‍👩‍👧‍👦", "👩‍👩‍👧‍👦", "👨‍👨‍👧‍👦", "🧑‍🤝‍🧑", "💏", "💑"
                ]
            )
        ),
        EmojiCategory(
            title: "Animals & Nature",
            systemImage: "leaf",
            emojis: emojiStrings(
                ranges: [
                    0x1F300...0x1F321,
                    0x1F324...0x1F32C,
                    0x1F330...0x1F343,
                    0x1F400...0x1F43F,
                    0x1F980...0x1F9AF
                ],
                extras: ["☀️", "☁️", "☔️", "❄️", "🌈", "🌱", "🌻", "🌲", "🍀"]
            )
        ),
        EmojiCategory(
            title: "Food & Drink",
            systemImage: "fork.knife",
            emojis: emojiStrings(
                ranges: [
                    0x1F32D...0x1F37F,
                    0x1F950...0x1F96F
                ],
                extras: ["🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🥝", "☕️"]
            )
        ),
        EmojiCategory(
            title: "Activity",
            systemImage: "figure.run",
            emojis: emojiStrings(
                ranges: [
                    0x1F3A0...0x1F3FF,
                    0x1F947...0x1F94F,
                    0x1F9E0...0x1F9FF
                ],
                extras: ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏆", "🎮", "🎵", "🎉"]
            )
        ),
        EmojiCategory(
            title: "Travel & Places",
            systemImage: "car",
            emojis: emojiStrings(
                ranges: [
                    0x1F5FA...0x1F5FF,
                    0x1F680...0x1F6FF,
                    0x1F700...0x1F70F
                ],
                extras: ["🏠", "🏡", "🏢", "🏥", "🏫", "⛺️", "🌋", "🗽"]
            )
        ),
        EmojiCategory(
            title: "Objects",
            systemImage: "lightbulb",
            emojis: emojiStrings(
                ranges: [
                    0x1F4A0...0x1F4FF,
                    0x1F500...0x1F5EF,
                    0x1F9E0...0x1F9FF
                ],
                extras: ["📱", "💻", "⌚️", "📷", "💡", "📚", "✏️", "🔑", "🎁"]
            )
        ),
        EmojiCategory(
            title: "Symbols",
            systemImage: "number",
            emojis: emojiStrings(
                ranges: [
                    0x1F170...0x1F1FF,
                    0x1F200...0x1F251,
                    0x2300...0x23FF,
                    0x2600...0x26FF,
                    0x2700...0x27BF
                ],
                extras: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "✅", "❌"]
            )
        ),
        EmojiCategory(
            title: "Flags",
            systemImage: "flag",
            emojis: flagEmojis
        )
    ]

    private static func emojiStrings(ranges: [ClosedRange<UInt32>], extras: [String]) -> [String] {
        var values = ranges.flatMap { range in
            range.compactMap { value -> String? in
                guard let scalar = UnicodeScalar(value),
                      scalar.properties.isEmoji,
                      !scalar.properties.isEmojiModifier else {
                    return nil
                }
                return String(scalar)
            }
        }
        values.append(contentsOf: extras)
        return unique(values)
    }

    private static var flagEmojis: [String] {
        var codes = "AC AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CP CR CU CV CW CX CY CZ DE DG DJ DK DM DO DZ EA EC EE EG EH ER ES ET EU FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU IC ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TA TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW"
            .split(separator: " ")
            .map(String.init)

        codes += ["EN", "GB-ENG", "GB-SCT", "GB-WLS"]
        return codes.compactMap { code in
            let letters = code.filter { $0.isLetter }
            guard letters.count == 2 else { return nil }
            let values = letters.uppercased().unicodeScalars.map { 0x1F1E6 + $0.value - 65 }
            guard values.count == 2,
                  let first = UnicodeScalar(values[0]),
                  let second = UnicodeScalar(values[1]) else {
                return nil
            }
            return String(first) + String(second)
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
