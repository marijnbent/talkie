import Foundation

enum DeepgramLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case arabic = "ar"
    case arabicUnitedArabEmirates = "ar-AE"
    case arabicSaudiArabia = "ar-SA"
    case arabicQatar = "ar-QA"
    case arabicKuwait = "ar-KW"
    case arabicSyria = "ar-SY"
    case arabicLebanon = "ar-LB"
    case arabicPalestine = "ar-PS"
    case arabicJordan = "ar-JO"
    case arabicEgypt = "ar-EG"
    case arabicSudan = "ar-SD"
    case arabicChad = "ar-TD"
    case arabicMorocco = "ar-MA"
    case arabicAlgeria = "ar-DZ"
    case arabicTunisia = "ar-TN"
    case arabicIraq = "ar-IQ"
    case arabicIran = "ar-IR"
    case armenian = "hy"
    case assamese = "asm"
    case asturian = "ast"
    case afrikaans = "afr"
    case amharic = "amh"
    case azerbaijani = "aze"
    case belarusian = "be"
    case bengali = "bn"
    case bosnian = "bs"
    case bulgarian = "bg"
    case burmese = "mya"
    case catalan = "ca"
    case cantonese = "yue"
    case cebuano = "ceb"
    case chichewa = "nya"
    case chineseCantonese = "zh-HK"
    case chineseMandarinSimplified = "zh"
    case chineseMandarinSimplifiedChina = "zh-CN"
    case chineseMandarinSimplifiedHans = "zh-Hans"
    case chineseMandarinTraditional = "zh-TW"
    case chineseMandarinTraditionalHant = "zh-Hant"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case danishDenmark = "da-DK"
    case dutch = "nl"
    case english = "en"
    case englishAmerican = "en-US"
    case englishAustralian = "en-AU"
    case englishBritish = "en-GB"
    case englishIndian = "en-IN"
    case englishNewZealand = "en-NZ"
    case estonian = "et"
    case filipino = "fil"
    case finnish = "fi"
    case flemish = "nl-BE"
    case french = "fr"
    case frenchCanadian = "fr-CA"
    case fulah = "ful"
    case galician = "glg"
    case ganda = "lug"
    case georgian = "kat"
    case german = "de"
    case germanSwiss = "de-CH"
    case greek = "el"
    case gujarati = "gu"
    case gujaratiIndia = "gu-IN"
    case hausa = "hau"
    case hebrew = "he"
    case hindi = "hi"
    case hungarian = "hu"
    case icelandic = "isl"
    case igbo = "ibo"
    case indonesian = "id"
    case irish = "gle"
    case italian = "it"
    case japanese = "ja"
    case javanese = "jav"
    case kabuverdianu = "kea"
    case kannada = "kn"
    case kazakh = "kaz"
    case khmer = "khm"
    case korean = "ko"
    case koreanSouthKorea = "ko-KR"
    case kurdish = "kur"
    case kyrgyz = "kir"
    case lao = "lao"
    case latvian = "lv"
    case lithuanian = "lt"
    case lingala = "lin"
    case luo = "luo"
    case luxembourgish = "ltz"
    case macedonian = "mk"
    case malay = "ms"
    case malayalam = "mal"
    case marathi = "mr"
    case maltese = "mlt"
    case mandarinChinese = "zho"
    case maori = "mri"
    case norwegian = "no"
    case mongolian = "mon"
    case nepali = "ne"
    case northernSotho = "nso"
    case persian = "fa"
    case polish = "pl"
    case portuguese = "pt"
    case portugueseBrazilian = "pt-BR"
    case portuguesePortugal = "pt-PT"
    case occitan = "oci"
    case odia = "ori"
    case pashto = "pus"
    case punjabi = "pa"
    case punjabiIndia = "pa-IN"
    case romanian = "ro"
    case russian = "ru"
    case serbian = "sr"
    case shona = "sna"
    case sindhi = "snd"
    case slovak = "sk"
    case slovenian = "sl"
    case somali = "som"
    case spanish = "es"
    case spanishLatinAmerica = "es-419"
    case swedish = "sv"
    case swedishSweden = "sv-SE"
    case swahili = "swa"
    case tagalog = "tl"
    case tamil = "ta"
    case telugu = "te"
    case tajik = "tgk"
    case thai = "th"
    case thaiThailand = "th-TH"
    case turkish = "tr"
    case ukrainian = "uk"
    case urdu = "ur"
    case umbundu = "umb"
    case uzbek = "uzb"
    case vietnamese = "vi"
    case welsh = "cym"
    case wolof = "wol"
    case xhosa = "xho"
    case yoruba = "yor"
    case zulu = "zul"

    static let defaultStarredLanguages: [DeepgramLanguage] = [.automatic, .english]

    var id: String { rawValue }

    var sortsBeforeAllOtherLanguages: Bool {
        self == .automatic
    }

    var deepgramCode: String {
        switch self {
        case .automatic:
            return "multi"
        default:
            return rawValue
        }
    }

    var menuBarAbbreviation: String {
        switch self {
        case .automatic:
            return "AUTO"
        default:
            return rawValue
                .split(separator: "-", maxSplits: 1)
                .first?
                .uppercased() ?? rawValue.uppercased()
        }
    }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .arabic:
            return "Arabic"
        case .arabicUnitedArabEmirates:
            return "Arabic (United Arab Emirates)"
        case .arabicSaudiArabia:
            return "Arabic (Saudi Arabia)"
        case .arabicQatar:
            return "Arabic (Qatar)"
        case .arabicKuwait:
            return "Arabic (Kuwait)"
        case .arabicSyria:
            return "Arabic (Syria)"
        case .arabicLebanon:
            return "Arabic (Lebanon)"
        case .arabicPalestine:
            return "Arabic (Palestine)"
        case .arabicJordan:
            return "Arabic (Jordan)"
        case .arabicEgypt:
            return "Arabic (Egypt)"
        case .arabicSudan:
            return "Arabic (Sudan)"
        case .arabicChad:
            return "Arabic (Chad)"
        case .arabicMorocco:
            return "Arabic (Morocco)"
        case .arabicAlgeria:
            return "Arabic (Algeria)"
        case .arabicTunisia:
            return "Arabic (Tunisia)"
        case .arabicIraq:
            return "Arabic (Iraq)"
        case .arabicIran:
            return "Arabic (Iran)"
        case .armenian:
            return "Armenian"
        case .assamese:
            return "Assamese"
        case .asturian:
            return "Asturian"
        case .afrikaans:
            return "Afrikaans"
        case .amharic:
            return "Amharic"
        case .azerbaijani:
            return "Azerbaijani"
        case .belarusian:
            return "Belarusian"
        case .bengali:
            return "Bengali"
        case .bosnian:
            return "Bosnian"
        case .bulgarian:
            return "Bulgarian"
        case .burmese:
            return "Burmese"
        case .catalan:
            return "Catalan"
        case .cantonese:
            return "Cantonese"
        case .cebuano:
            return "Cebuano"
        case .chichewa:
            return "Chichewa"
        case .chineseCantonese:
            return "Chinese (Cantonese)"
        case .chineseMandarinSimplified:
            return "Chinese (Mandarin, Simplified)"
        case .chineseMandarinSimplifiedChina:
            return "Chinese (Mandarin, Simplified, China)"
        case .chineseMandarinSimplifiedHans:
            return "Chinese (Mandarin, Simplified script)"
        case .chineseMandarinTraditional:
            return "Chinese (Mandarin, Traditional)"
        case .chineseMandarinTraditionalHant:
            return "Chinese (Mandarin, Traditional script)"
        case .croatian:
            return "Croatian"
        case .czech:
            return "Czech"
        case .danish:
            return "Danish"
        case .danishDenmark:
            return "Danish (Denmark)"
        case .dutch:
            return "Dutch"
        case .english:
            return "English"
        case .englishAmerican:
            return "English (US)"
        case .englishAustralian:
            return "English (Australia)"
        case .englishBritish:
            return "English (UK)"
        case .englishIndian:
            return "English (India)"
        case .englishNewZealand:
            return "English (New Zealand)"
        case .estonian:
            return "Estonian"
        case .filipino:
            return "Filipino"
        case .finnish:
            return "Finnish"
        case .flemish:
            return "Flemish"
        case .french:
            return "French"
        case .frenchCanadian:
            return "French (Canada)"
        case .fulah:
            return "Fulah"
        case .galician:
            return "Galician"
        case .ganda:
            return "Ganda"
        case .georgian:
            return "Georgian"
        case .german:
            return "German"
        case .germanSwiss:
            return "German (Switzerland)"
        case .greek:
            return "Greek"
        case .gujarati:
            return "Gujarati"
        case .gujaratiIndia:
            return "Gujarati (India)"
        case .hausa:
            return "Hausa"
        case .hebrew:
            return "Hebrew"
        case .hindi:
            return "Hindi"
        case .hungarian:
            return "Hungarian"
        case .icelandic:
            return "Icelandic"
        case .igbo:
            return "Igbo"
        case .indonesian:
            return "Indonesian"
        case .irish:
            return "Irish"
        case .italian:
            return "Italian"
        case .japanese:
            return "Japanese"
        case .javanese:
            return "Javanese"
        case .kabuverdianu:
            return "Kabuverdianu"
        case .kannada:
            return "Kannada"
        case .kazakh:
            return "Kazakh"
        case .khmer:
            return "Khmer"
        case .korean:
            return "Korean"
        case .koreanSouthKorea:
            return "Korean (South Korea)"
        case .kurdish:
            return "Kurdish"
        case .kyrgyz:
            return "Kyrgyz"
        case .lao:
            return "Lao"
        case .latvian:
            return "Latvian"
        case .lithuanian:
            return "Lithuanian"
        case .lingala:
            return "Lingala"
        case .luo:
            return "Luo"
        case .luxembourgish:
            return "Luxembourgish"
        case .macedonian:
            return "Macedonian"
        case .malay:
            return "Malay"
        case .malayalam:
            return "Malayalam"
        case .marathi:
            return "Marathi"
        case .maltese:
            return "Maltese"
        case .mandarinChinese:
            return "Mandarin Chinese"
        case .maori:
            return "Māori"
        case .norwegian:
            return "Norwegian"
        case .mongolian:
            return "Mongolian"
        case .nepali:
            return "Nepali"
        case .northernSotho:
            return "Northern Sotho"
        case .persian:
            return "Persian"
        case .polish:
            return "Polish"
        case .portuguese:
            return "Portuguese"
        case .portugueseBrazilian:
            return "Portuguese (Brazil)"
        case .portuguesePortugal:
            return "Portuguese (Portugal)"
        case .occitan:
            return "Occitan"
        case .odia:
            return "Odia"
        case .pashto:
            return "Pashto"
        case .punjabi:
            return "Punjabi"
        case .punjabiIndia:
            return "Punjabi (India)"
        case .romanian:
            return "Romanian"
        case .russian:
            return "Russian"
        case .serbian:
            return "Serbian"
        case .shona:
            return "Shona"
        case .sindhi:
            return "Sindhi"
        case .slovak:
            return "Slovak"
        case .slovenian:
            return "Slovenian"
        case .somali:
            return "Somali"
        case .spanish:
            return "Spanish"
        case .spanishLatinAmerica:
            return "Spanish (Latin America)"
        case .swedish:
            return "Swedish"
        case .swedishSweden:
            return "Swedish (Sweden)"
        case .swahili:
            return "Swahili"
        case .tagalog:
            return "Tagalog"
        case .tamil:
            return "Tamil"
        case .telugu:
            return "Telugu"
        case .tajik:
            return "Tajik"
        case .thai:
            return "Thai"
        case .thaiThailand:
            return "Thai (Thailand)"
        case .turkish:
            return "Turkish"
        case .ukrainian:
            return "Ukrainian"
        case .urdu:
            return "Urdu"
        case .umbundu:
            return "Umbundu"
        case .uzbek:
            return "Uzbek"
        case .vietnamese:
            return "Vietnamese"
        case .welsh:
            return "Welsh"
        case .wolof:
            return "Wolof"
        case .xhosa:
            return "Xhosa"
        case .yoruba:
            return "Yoruba"
        case .zulu:
            return "Zulu"
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }
        return displayName.localizedCaseInsensitiveContains(trimmedQuery)
    }

    static func normalizedStarredLanguages(
        _ languages: [DeepgramLanguage],
        fallback: [DeepgramLanguage] = defaultStarredLanguages
    ) -> [DeepgramLanguage] {
        var seen = Set<DeepgramLanguage>()
        let normalized = languages.filter { seen.insert($0).inserted }
        return normalized.isEmpty ? fallback : normalized
    }

    static func starredLanguages(from rawValues: [String]?) -> [DeepgramLanguage] {
        guard let rawValues else { return defaultStarredLanguages }
        let languages = rawValues.compactMap(DeepgramLanguage.init(rawValue:))
        return normalizedStarredLanguages(languages)
    }

    static func sortedForMenuBar(_ languages: [DeepgramLanguage]) -> [DeepgramLanguage] {
        languages.sorted { compareForDisplay($0, $1) == .orderedAscending }
    }

    static func nextStarredLanguage(
        after currentLanguage: DeepgramLanguage,
        starredLanguages: [DeepgramLanguage],
        availableLanguages: [DeepgramLanguage] = DeepgramLanguage.allCases
    ) -> DeepgramLanguage {
        let languages = sortedForMenuBar(
            normalizedStarredLanguages(
                starredLanguages.filter(availableLanguages.contains),
                fallback: [availableLanguages.first ?? .automatic]
            )
        )
        guard let currentIndex = languages.firstIndex(of: currentLanguage) else {
            return languages[0]
        }

        return languages[(currentIndex + 1) % languages.count]
    }

    static func sortedForSettings(
        _ languages: [DeepgramLanguage],
        starred: Set<DeepgramLanguage>
    ) -> [DeepgramLanguage] {
        languages.sorted { lhs, rhs in
            let lhsIsStarred = starred.contains(lhs)
            let rhsIsStarred = starred.contains(rhs)

            if lhsIsStarred != rhsIsStarred {
                return lhsIsStarred && !rhsIsStarred
            }

            return compareForDisplay(lhs, rhs) == .orderedAscending
        }
    }

    private static func compareForDisplay(_ lhs: DeepgramLanguage, _ rhs: DeepgramLanguage) -> ComparisonResult {
        if lhs.sortsBeforeAllOtherLanguages != rhs.sortsBeforeAllOtherLanguages {
            return lhs.sortsBeforeAllOtherLanguages ? .orderedAscending : .orderedDescending
        }

        return lhs.displayName.localizedStandardCompare(rhs.displayName)
    }
}

extension DeepgramLanguage {
    /// Nova-3's current language catalog. The ElevenLabs-only cases stay in the
    /// shared enum so saved history and app overrides can migrate safely.
    static let deepgramNova3Languages: [DeepgramLanguage] = {
        allCases.filter { !elevenLabsOnlyLanguages.contains($0) }
    }()

    /// Canonical language choices for ElevenLabs. Regional variants are not
    /// included because ElevenLabs accepts a language code, not a regional hint.
    static let elevenLabsLanguages: [DeepgramLanguage] = [
        .automatic,
        .afrikaans,
        .amharic,
        .arabic,
        .armenian,
        .assamese,
        .asturian,
        .azerbaijani,
        .belarusian,
        .bengali,
        .bosnian,
        .bulgarian,
        .burmese,
        .catalan,
        .cantonese,
        .cebuano,
        .chichewa,
        .croatian,
        .czech,
        .danish,
        .dutch,
        .english,
        .estonian,
        .filipino,
        .finnish,
        .french,
        .fulah,
        .galician,
        .ganda,
        .georgian,
        .german,
        .greek,
        .gujarati,
        .hausa,
        .hebrew,
        .hindi,
        .hungarian,
        .icelandic,
        .igbo,
        .indonesian,
        .irish,
        .italian,
        .japanese,
        .javanese,
        .kabuverdianu,
        .kannada,
        .kazakh,
        .khmer,
        .korean,
        .kurdish,
        .kyrgyz,
        .lao,
        .latvian,
        .lithuanian,
        .lingala,
        .luo,
        .luxembourgish,
        .macedonian,
        .malay,
        .malayalam,
        .maltese,
        .mandarinChinese,
        .maori,
        .marathi,
        .mongolian,
        .nepali,
        .northernSotho,
        .norwegian,
        .occitan,
        .odia,
        .pashto,
        .persian,
        .polish,
        .portuguese,
        .punjabi,
        .romanian,
        .russian,
        .serbian,
        .shona,
        .sindhi,
        .slovak,
        .slovenian,
        .somali,
        .spanish,
        .swahili,
        .swedish,
        .tajik,
        .tamil,
        .telugu,
        .thai,
        .turkish,
        .ukrainian,
        .umbundu,
        .urdu,
        .uzbek,
        .vietnamese,
        .welsh,
        .wolof,
        .xhosa,
        .yoruba,
        .zulu,
    ]

    private static let elevenLabsOnlyLanguages: Set<DeepgramLanguage> = [
        .afrikaans,
        .amharic,
        .assamese,
        .asturian,
        .azerbaijani,
        .burmese,
        .cantonese,
        .cebuano,
        .chichewa,
        .filipino,
        .fulah,
        .galician,
        .ganda,
        .georgian,
        .hausa,
        .icelandic,
        .igbo,
        .irish,
        .javanese,
        .kabuverdianu,
        .kazakh,
        .khmer,
        .kurdish,
        .kyrgyz,
        .lao,
        .lingala,
        .luo,
        .luxembourgish,
        .malayalam,
        .maltese,
        .mandarinChinese,
        .maori,
        .mongolian,
        .northernSotho,
        .occitan,
        .odia,
        .pashto,
        .shona,
        .sindhi,
        .somali,
        .swahili,
        .tajik,
        .umbundu,
        .uzbek,
        .welsh,
        .wolof,
        .xhosa,
        .yoruba,
        .zulu,
    ]
}
