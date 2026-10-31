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
 * game: they play as English, with English's files from their pack.  Polish's
 * and Turkish's texts spell their letters with accented ones of the game's
 * fonts, whose textures in their packs draw them as the Polish or Turkish
 * ones (language_game_letters does the same for texts of ours).
 *
 * Movie subtitles, NFSU2_SUBTITLES=1 (default off, as the original game):
 * the movies' subtitles (SUBTITLES/<movie>: when to show which of the
 * language's texts) are shown by the game's territory, not by its language:
 * the check, sub_0050d350 (the front end's movies and the next in-game one)
 * and its copy in InGamePlayMovie's constructor (sub_00553950), shows them
 * in territories 2 and 5 for every language but English, in 4 and 12 for
 * all; both v1.2 executables are territory 6 (European) or 0 (North
 * American), so they never do.  With NFSU2_SUBTITLES=1 the last of the
 * territory tests, "== 12" (0x50d388 in both builds; 0x553a72, 0x553a62 in
 * the North American build), is made true for a language whose text has the
 * movies' lines: the PSA's first one ("Hi, I'm Brooke Burke"), which the
 * dubbed French, German, Italian and Spanish texts leave empty (the game
 * would still draw an empty line's bar).  The retail English text cuts the
 * lines off at their first apostrophe ("But if you"), so English shows them
 * only with its pack: VileStuff's English Subtitles Fixed, which the
 * launcher builds into LANGPACKS/english (launcher/LanguagePacks.swift).
 *
 * Texts of our own (language_add_text): texts the game shows but has none of
 * (the free-roam race questions' buttons, roam_game.c) go into its language
 * table under names of ours, so that it looks them up as its own.  The table
 * is a sorted {hash, char*} array that the game only points into its
 * language chunk (sub_005125b0 loads it, sub_004ffae0 clears it).  Each frame
 * (the main-loop hook, 0x581485; 0x581475 in the North American build) a
 * table that is not ours, or one older than a text added since, is replaced
 * by a copy with every text of ours merged in by hash (unsigned, as
 * sub_004ff9d0 compares; a hash the game has keeps the game's), their
 * strings after the entries.  The game's own array stays as it was, for the
 * next copy.
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
/* The language played, as NFSU2_LANGUAGE names it ("english" ... "turkish"). */
const char *language_name(void){ return g_lang ? g_lang->key : "english"; }

/* ---- the game's texts ------------------------------------------------------- */
void dispatch_indirect(CPU *c, uint32_t addr);
#define G_LANG       GA(0x008383d8u)   /* the loaded texts: { hash, char * } sorted by hash */
#define G_LANG_N     GA(0x008383d0u)   /* how many */
#define FN_NEW       GA(0x00575630u)   /* cdecl (size): operator new */
#define HOOK_FRAME   HOOK_SITE(0x00581485u)   /* GameLoop, before its second debug no-op call (roam.c's main-loop hook) */

/* The game's text for a hash in the language it plays in: sub_004ff9d0's
 * binary search.  0 before a language is loaded, or for a hash it lacks. */
uint32_t language_text(uint32_t hash){
    uint32_t tab = MR32(G_LANG), n = MR32(G_LANG_N);
    if (!tab || !n || n > 0x100000u || !mem_is_committed(tab) || !mem_is_committed(tab + 8u*n - 1u)) return 0;
    uint32_t lo = 0, hi = n;
    while (lo < hi){
        uint32_t mid = lo + (hi - lo) / 2, h = MR32(tab + 8u*mid);
        if (h == hash) return MR32(tab + 8u*mid + 4u);
        if (h < hash) lo = mid + 1; else hi = mid;
    }
    return 0;
}
static int text_is(uint32_t s, const char *want){
    size_t n = strlen(want) + 1;
    return s && mem_is_committed(s) && mem_is_committed(s + (uint32_t)n - 1u) && !memcmp(g_mem + s, want, n);
}

/* ---- texts of our own ------------------------------------------------------- */
#define OWN_MAX     16
static struct { uint32_t hash; char text[1024]; } g_own[OWN_MAX];
static int g_nown, g_own_merged;            /* texts named; how many of them the copy has */
static uint32_t g_own_copy, g_own_from, g_own_from_n;   /* the copy, while the game points at it; the game's array */

/* name -> its hash (bStringHash, sub_0043db50), the text in the game's letters */
uint32_t language_add_text(const char *name, const char *text){
    uint32_t h = 0xffffffffu;
    for (const char *s = name; *s; s++) h = h * 33u + (uint8_t)*s;
    int i = 0;
    while (i < g_nown && g_own[i].hash != h) i++;
    if (i == OWN_MAX){ fprintf(stderr, "language: no room for the text %s\n", name); return h; }
    if (i == g_nown) g_nown++;
    g_own[i].hash = h;
    snprintf(g_own[i].text, sizeof g_own[i].text, "%s", text);
    g_own_merged = -1;                          /* a new copy, also for a text changed */
    return h;
}

/* operator new in guest memory, from the main-loop hook */
static uint32_t guest_new(CPU *c, uint32_t size){
    CPU save = *c;
    c->esp = (c->esp - 256u) & ~15u;
    PUSH32(size);
    PUSH32(HOOK_FRAME);                         /* the hook's address as the return address: the callee's ret pops it */
    dispatch_indirect(c, FN_NEW);
    uint32_t r = c->eax;
    *c = save;
    return r;
}

/* The main-loop hook (also roam_game.c, at once when it adds its texts). */
void language_texts_frame(CPU *c){
    uint32_t t = MR32(G_LANG), n = MR32(G_LANG_N);
    if (!g_nown || !t || !n || n > 0x100000u) return;
    if (t == g_own_copy){
        if (g_own_merged == g_nown) return;
        t = g_own_from; n = g_own_from_n;
    }
    if (!mem_is_committed(t) || !mem_is_committed(t + 8u*n - 1u)) return;
    int ord[OWN_MAX];
    uint32_t strs = 0;
    for (int i = 0; i < g_nown; i++){ ord[i] = i; strs += (uint32_t)strlen(g_own[i].text) + 1u; }
    for (int i = 1; i < g_nown; i++)
        for (int j = i; j > 0 && g_own[ord[j - 1]].hash > g_own[ord[j]].hash; j--){ int x = ord[j]; ord[j] = ord[j - 1]; ord[j - 1] = x; }
    uint32_t mem = guest_new(c, (n + (uint32_t)g_nown) * 8u + strs);
    if (!mem){ fprintf(stderr, "language: guest memory for our texts failed\n"); g_own_copy = t; g_own_merged = g_nown; return; }
    uint32_t sp = mem + (n + (uint32_t)g_nown) * 8u, sa[OWN_MAX];
    for (int i = 0; i < g_nown; i++){
        size_t l = strlen(g_own[i].text) + 1u;
        memcpy(g_mem + sp, g_own[i].text, l); sa[i] = sp; sp += (uint32_t)l;
    }
    uint32_t o = 0; int k = 0, kept = 0;
    for (uint32_t i = 0; i <= n; i++){
        uint32_t h = i < n ? MR32(t + 8u*i) : 0xffffffffu;
        while (k < g_nown && g_own[ord[k]].hash <= h){
            if (g_own[ord[k]].hash == h && i < n){ k++; kept++; continue; }   /* the game has the name already */
            MR32(mem + 8u*o) = g_own[ord[k]].hash; MR32(mem + 8u*o + 4u) = sa[ord[k]]; o++; k++;
        }
        if (i < n){ MR32(mem + 8u*o) = h; MR32(mem + 8u*o + 4u) = MR32(t + 8u*i + 4u); o++; }
    }
    MR32(G_LANG) = mem; MR32(G_LANG_N) = o;
    g_own_copy = mem; g_own_from = t; g_own_from_n = n; g_own_merged = g_nown;
    fprintf(stderr, "language: %d text%s of our own added to the game's %u%s\n", g_nown - kept, g_nown - kept == 1 ? "" : "s", n,
            kept ? " (some names the game has already: the game's stay)" : "");
}

/* A text of ours (UTF-8) in the game's letters: Latin-1, as its language files
 * write theirs; Polish's letters as its pack's fonts draw them (e-ogonek 0xBF,
 * l-stroke 0xEE, s-acute 0xE2 ...), Turkish's too (dotless i 0xED, s-cedilla
 * 0xFF, g-breve 0xFD ...); a letter the fonts lack as '?'.  Korean, Chinese,
 * Japanese, Thai and Russian draw ASCII as it is (car names), not Latin-1's
 * accented letters. */
void language_game_letters(const char *utf8, char *out, size_t n){
    static const struct { uint16_t u; uint8_t b; } PL[] = {
        { 0x105, 0xe7 }, { 0x107, 0xe9 }, { 0x119, 0xbf }, { 0x142, 0xee }, { 0x144, 0xf1 }, { 0xf3, 0xf3 },
        { 0x15b, 0xe2 }, { 0x17a, 0xeb }, { 0x17c, 0xe1 }, { 0x104, 0xfd }, { 0x106, 0xc8 }, { 0x118, 0xc7 },
        { 0x141, 0xfa }, { 0x143, 0xd1 }, { 0xd3, 0xd3 }, { 0x15a, 0xda }, { 0x17b, 0xc9 },
    }, TR[] = {
        { 0x131, 0xed }, { 0x130, 0xcd }, { 0x15f, 0xff }, { 0x15e, 0xfe }, { 0x11f, 0xfd }, { 0x11e, 0xdd },
    };
    const char *key = language_name();
    int polish = !strcmp(key, "polish"), turkish = !strcmp(key, "turkish");
    int latin = !(g_lang && g_lang->fonts) && strcmp(key, "russian");
    const uint8_t *s = (const uint8_t *)utf8;
    size_t o = 0;
    if (!n) return;
    while (*s && o + 1 < n){
        uint32_t u = *s++;
        if (u >= 0xc0){
            int more = u >= 0xf0 ? 3 : u >= 0xe0 ? 2 : 1;
            u &= 0x3fu >> more;
            while (more-- && (*s & 0xc0) == 0x80) u = u << 6 | (*s++ & 0x3fu);
        }
        uint8_t b = '?';
        if (u < 0x80) b = (uint8_t)u;
        else if (u == 0x2019 || u == 0x2018) b = '\'';
        else if (u == 0x2013 || u == 0x2014) b = '-';
        else if (polish){ for (unsigned i = 0; i < sizeof PL / sizeof PL[0]; i++) if (PL[i].u == u) b = PL[i].b; }
        else if (turkish && u >= 0x100){ for (unsigned i = 0; i < sizeof TR / sizeof TR[0]; i++) if (TR[i].u == u) b = TR[i].b; }
        else if (latin && u >= 0xa0 && u < 0x100) b = (uint8_t)u;
        out[o++] = (char)b;
    }
    out[o] = 0;
}

/* ---- movie subtitles -------------------------------------------------------- */
static int subtitles_on(void){
    static int on = -1;
    if (on < 0){
        const char *e = getenv("NFSU2_SUBTITLES");
        on = e && (!strcmp(e, "1") || !strcasecmp(e, "on") || !strcasecmp(e, "yes"));
        fprintf(stderr, "language: movie subtitles %s\n", on ? "on where the language's text has the movies' lines" : "off (original)");
    }
    return on;
}
/* Has the language's text the movies' lines, whole? */
static int text_has_lines(void){
    uint32_t psa = language_text(0x03812413u);  /* "Hi, I'm Brooke Burke and I play ..." */
    uint32_t cut = language_text(0xd1619869u);  /* retail English: "But if you" */
    return psa && mem_is_committed(psa) && MR8(psa) && !text_is(cut, "But if you");
}

/* TEXTFAKE=<name>=<UTF-8 text> (test): adds the text, in the game's letters,
 * and logs the bytes the game's own lookup finds for its name. */
static void text_fake(void){
    static int st = -1; static uint32_t h;
    if (st < 0){
        const char *e = getenv("TEXTFAKE"), *eq = e ? strchr(e, '=') : 0;
        st = 0;
        if (eq && eq > e){
            char name[64], text[256];
            snprintf(name, sizeof name, "%.*s", (int)(eq - e), e);
            language_game_letters(eq + 1, text, sizeof text);
            h = language_add_text(name, text); st = 1;
        }
    }
    uint32_t s = st == 1 ? language_text(h) : 0;
    if (s && mem_is_committed(s)){
        st = 2;
        fprintf(stderr, "language: TEXTFAKE 0x%08x found by the game's lookup:", h);
        for (uint32_t i = 0; i < 64 && mem_is_committed(s + i) && MR8(s + i); i++) fprintf(stderr, " %02x", MR8(s + i));
        fprintf(stderr, "\n");
    }
}

/* Called from guest_hook (debug.c) BEFORE the instruction at ip runs. */
int language_hook(CPU *c, uint32_t ip){
    if (ip == HOOK_FRAME){ text_fake(); language_texts_frame(c); return 0; }   /* roam.c's site too */
    if (ip == HOOK_SITE(0x0050d388u) || ip == HOOK_SITE(0x00553a72u)){          /* cmp eax, 0xc */
        static unsigned shown;
        if (subtitles_on() && text_has_lines()){
            c->eax = 0xcu;
            if (shown++ < 2) fprintf(stderr, "language: this movie gets its subtitles\n");
        }
        return 1;
    }
    return 0;
}

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
