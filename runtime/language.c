/* language.c - the game's language: NFSU2_LANGUAGE.
 *
 *   english, french, german, italian, spanish, dutch, swedish, danish,
 *   korean, chinese, japanese, thai, russian, portuguese, polish, turkish
 *
 * SPEED2.EXE reads its language once at startup from the registry value
 * "Language" (sub_005b7700, its compare loop at 0x5b7980; 0x5b76f0 and
 * 0x5b7970 in the North American build) against its names at 0x7fca08
 * ("English US" ... "Thai"), keeps the id in 0x7fca00 and loads
 * LANGUAGES\<NAME>.BIN through its language table (0x7f7020: 16-byte entries
 * id, name, file, font block; the current id at 0x7f70d0, right after the
 * table).  The names, the table and the code are the same in both builds.
 * For French, German, Italian, Spanish and Japanese it also opens its dubbed
 * speech bank, speech/UG2_Speech_FR/GR/IT/SP/JP.*.  win32_ext.c answers
 * "Language" with language_registry(); without NFSU2_LANGUAGE it answers as
 * before (a saved value, otherwise English).
 *
 * What a language needs beyond the retail folder (the dubbed speech and
 * movies, the full Chinese, Japanese and Thai text with the fonts drawn for
 * it, Russian, Portuguese, Polish, Turkish) can come from LANGPACKS/<language>
 * in the game folder, laid out like the game folder: fileio.c reads a file
 * there in place of the game folder's file of the same path.  A language
 * without a pack plays its text with English voices and movies.
 *
 * Two things the exe cannot do by itself, which the multilingual mod's
 * U2_ThaiSupport.asi patches into its code; here they are changes to its
 * data, before the game runs:
 *  - the language pool (sub_004ff680, "LanguageMemoryPool") is sized for the
 *    fonts of the English entry (144 KB), but the Korean, Chinese, Japanese
 *    and Thai fonts are 848 KB: they would not fit.  Its font size table
 *    (0x7f6de8, read only there) gives the first English font the difference.
 *  - the table ends at Japanese (id 10): Thai (11) is in the registry names
 *    but has no entry.  In a Thai game Japanese's entry becomes Thai's: its
 *    id, its name and file ("JAPANESE" -> "THAILAND", the same length) and
 *    the font hashes of its block.
 * Russian, Portuguese (Brazil's), Polish and Turkish are no languages of the
 * game: they play as English, with English's files from their pack.
 *
 * Ported from th0mk's nfsu2-web runtime/language.c (MIT). */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

int fileio_set_language_pack(const char *rel);

#define FONT_SIZES  GA(0x007f6de8u)   /* 15 x { hash, size }, read by sub_004ff680 only */
#define LATIN_FONTS GA(0x007f6e60u)   /* font blocks: the hashes, then 0 */
#define KO_FONTS    GA(0x007f6ed0u)
#define JA_FONTS    GA(0x007f6f40u)
#define ZH_FONTS    GA(0x007f6fb0u)
#define JA_ENTRY    GA(0x007f70c0u)   /* { 10, "JAPANESE", "LANGUAGES\JAPANESE.BIN", JA_FONTS } */
#define JA_NAME     GA(0x0079a70cu)   /* NA 0x79a704 */
#define JA_FILE     GA(0x0079a6f4u)   /* NA 0x79a6ec */

static const struct lang { const char *key, *reg; uint32_t fonts; int thai; } LANGS[] = {
    /* "English" is not one of the game's names: the runtime has always
     * answered it, and the game then stays on its default, English US */
    { "english",    "English", 0, 0 },
    { "french",     "French", 0, 0 },
    { "german",     "German", 0, 0 },
    { "italian",    "Italian", 0, 0 },
    { "spanish",    "Spanish", 0, 0 },
    { "dutch",      "Dutch", 0, 0 },
    { "swedish",    "Swedish", 0, 0 },
    { "danish",     "Danish", 0, 0 },
    { "korean",     "Korean", KO_FONTS, 0 },
    { "chinese",    "Chinese (Traditional)", ZH_FONTS, 0 },
    { "japanese",   "Japanese", JA_FONTS, 0 },
    { "thai",       "Thai", JA_FONTS, 1 },          /* in Japanese's entry and block */
    { "russian",    "English", 0, 0 },
    { "portuguese", "English", 0, 0 },
    { "polish",     "English", 0, 0 },
    { "turkish",    "English", 0, 0 },
};
static const struct lang *g_lang;   /* 0: NFSU2_LANGUAGE not set */
static const uint32_t THAI_FONTS[4] = { 0x4815619du, 0xa87927beu, 0xa73823ffu, 0xbbba71c2u };

/* The registry's "Language" for NFSU2_LANGUAGE, 0 when it is not set. */
const char *language_registry(void){ return g_lang ? g_lang->reg : 0; }

/* what a font block's hashes add up to in the size table (sub_004ff680's sum) */
static uint32_t fonts_total(uint32_t block){
    uint32_t t = 0;
    for (uint32_t h; (h = MR32(block)) != 0; block += 4)
        for (uint32_t i = 0; i < 15; i++)
            if (MR32(FONT_SIZES + 8*i) == h && (int32_t)MR32(FONT_SIZES + 8*i + 4) > 0) t += MR32(FONT_SIZES + 8*i + 4);
    return t;
}

void language_install(void){
    const char *e = getenv("NFSU2_LANGUAGE");
    if (!e || !*e) return;
    size_t i, n = sizeof LANGS / sizeof LANGS[0];
    for (i = 0; i < n && strcasecmp(e, LANGS[i].key); i++) {}
    if (i == n){ fprintf(stderr, "language: \"%s\" is not one of the game's, English it is\n", e); i = 0; }
    g_lang = &LANGS[i];

    char pack[64]; snprintf(pack, sizeof pack, "LANGPACKS/%s", g_lang->key);
    int files = fileio_set_language_pack(pack);
    fprintf(stderr, "language: %s (registry \"%s\"), %s: %d file%s\n", g_lang->key, g_lang->reg,
            pack, files, files == 1 ? "" : "s");
    if (!g_lang->fonts) return;

    /* only on the data this was checked against */
    if (MR32(FONT_SIZES) != MR32(LATIN_FONTS) || MR32(FONT_SIZES + 4) != 0
        || MR32(JA_ENTRY) != 10 || MR32(JA_ENTRY + 4) != JA_NAME || MR32(JA_ENTRY + 8) != JA_FILE
        || MR32(JA_ENTRY + 12) != JA_FONTS || MR32(JA_FONTS + 16) != 0
        || memcmp(g_mem + JA_NAME, "JAPANESE", 9) || memcmp(g_mem + JA_FILE, "LANGUAGES\\JAPANESE.BIN", 23)){
        fprintf(stderr, "language: the exe's language table is not the one expected, left as it is\n");
        return;
    }
    if (g_lang->thai){
        MR32(JA_ENTRY) = 11;
        memcpy(g_mem + JA_NAME, "THAILAND", 8);
        memcpy(g_mem + JA_FILE + 10, "THAILAND", 8);
        for (int k = 0; k < 4; k++) MR32(JA_FONTS + 4u*k) = THAI_FONTS[k];
    }
    uint32_t need = fonts_total(g_lang->fonts), have = fonts_total(LATIN_FONTS);
    if (need > have){
        MR32(FONT_SIZES + 4) = need - have;
        fprintf(stderr, "language: the language pool is sized for its fonts (%u KB, not %u)\n", need >> 10, have >> 10);
    }
}
