// Port of TamaPoke's i18n.cpp lookups (MIT, (c) 2026 Quique Tortosa).
package com.pokewatch.game

object Text {
    const val LANG_ES = 0
    const val LANG_EN = 1
    const val LANG_FR = 2
    const val LANG_DE = 3
    const val LANG_JA = 6
    const val LANG_KO = 7
    val LANG_COUNT = StringTables.LANG_CODES.size

    var lang = LANG_EN

    fun t(id: S): String = StringTables.STRINGS[lang][id.ordinal]

    /** T(id) filled printf-style. The firmware's %u/%lu become %d here. */
    fun f(id: S, vararg args: Any): String =
        t(id).replace("%lu", "%d").replace("%u", "%d").format(*args)

    fun medalName(i: Int) = StringTables.MED_NAME[lang][i]
    fun medalLabel(i: Int) = StringTables.MED_LBL[lang][i]
    fun medalDesc(i: Int) = StringTables.MED_DSC[lang][i]

    fun dexName(dex: Int): String {
        if (dex < 1 || dex > DEX_COUNT) return DexTables.NAME[0]
        val n = when (lang) {
            LANG_FR -> DexTables.NAME_FR[dex]
            LANG_DE -> DexTables.NAME_DE[dex]
            LANG_JA -> DexTables.NAME_JA[dex]
            LANG_KO -> DexTables.NAME_KO[dex]
            else -> null
        }
        return n ?: DexTables.NAME[dex]
    }
}
