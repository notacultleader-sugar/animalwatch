// Port of TamaPoke's i18n.cpp lookups (MIT, (c) 2026 Quique Tortosa).
import Foundation

enum I18n {
    static let LANG_ES = 0
    static let LANG_EN = 1
    static let LANG_FR = 2
    static let LANG_DE = 3
    static let LANG_JA = 6
    static let LANG_KO = 7
    static let LANG_COUNT = StringTables.LANG_CODES.count

    static var lang = LANG_EN

    static func t(_ id: S) -> String { StringTables.STRINGS[lang][id.rawValue] }

    /// T(id) filled printf-style. The tables only use %s, %d, %u and %lu, each
    /// taking the next argument in order, so they are substituted directly.
    static func f(_ id: S, _ args: Any...) -> String { format(t(id), args) }

    static func format(_ fmt: String, _ args: [Any]) -> String {
        var out = ""
        var next = 0
        var it = Array(fmt)[...]
        while let c = it.popFirst() {
            if c != "%" { out.append(c); continue }
            if it.first == "%" { it.removeFirst(); out.append("%"); continue }
            if it.first == "l" { it.removeFirst() }
            guard let spec = it.popFirst() else { break }
            if "sdu".contains(spec), next < args.count {
                out += "\(args[next])"
                next += 1
            }
        }
        return out
    }

    static func medalName(_ i: Int) -> String { StringTables.MED_NAME[lang][i] }
    static func medalLabel(_ i: Int) -> String { StringTables.MED_LBL[lang][i] }
    static func medalDesc(_ i: Int) -> String { StringTables.MED_DSC[lang][i] }

    static func dexName(_ dex: Int) -> String {
        if dex < 1 || dex > DEX_COUNT { return DexTables.NAME[0] }
        let n: String?
        switch lang {
        case LANG_FR: n = DexTables.NAME_FR[dex]
        case LANG_DE: n = DexTables.NAME_DE[dex]
        case LANG_JA: n = DexTables.NAME_JA[dex]
        case LANG_KO: n = DexTables.NAME_KO[dex]
        default: n = nil
        }
        return n ?? DexTables.NAME[dex]
    }
}
