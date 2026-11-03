/* names_unit.c -- names that read as a slur (runtime/names.h): the ways round
 * the lists are refused, and the other words with those letters are not.  The
 * names are nfsu2-web's web/test/names.test.mjs at e75e10d (the live server's
 * names made up the same ways), so the game, the launcher and the server agree.
 * Its other scripts' look-alikes (fullwidth, Greek, Cyrillic) are the page's
 * and the server's to fold: names.h reads the ASCII letters, as there.
 *   tests/names_unit.sh
 * Ported from th0mk's nfsu2-web web/test/names.test.mjs (MIT). */
#include "names.h"
#include <stdio.h>

static const char *const BLOCKED[] = {
    "nigger", "N1gg3r", "n i g g e r", "n.i.g.g.a", "NiQQa", "nlgga", "n!gga", "niiiigggaaa", "xXn1gg4Xx", "FAG",
    "f4g", "F A G", "f4g_42", "XxFagXx", "fags", "Faaag", "faggot", "f@gg0t", "fa66ot", "tr4nny", "Trannie",
    "r3tard", "ibne", "iBnE_34", "wetback", "beaner", "Ch1nk", "g00k", "sp1cs", "paki", "k1ke", "dyke", "c00n",
    "XxCoonXx", "towelhead", "sandnigger", "junglebunny", "ni99a", "NI99A", "nigga99", "Fag42", "Big1Fag",
    "Mr5Coon", "trannies", "Dykes", "Van_Fag", "Hitler", "Hitler3858", "adolfhitler", "AdolfH", "H1tl3r", "gitler",
    "Himmler", "zigHael", "NAZZI", "JewsHunter", "nigahunter", "Niga", "NigaBoi", "Nig4", "MEGANIGA", "KneeGro",
    "CzarnuchJebany", "CHURKA", "xoxol", "pidor", "PIDARAZ", "vladpidr", "cwel666", "gigacwel", "Mongoloid",
    "TALIBAN", "Et_Binladen", "samrapist", "RapeAddict", "ASphaltMolester", "1488", "Sam1488", "kkk1488",
    "Sam14881488", "Nate_Higgers", "NateHiggers", "N8_Higgers", "Niger", "Nigerz", "xN1gerx", "NIG_ER", "BigNig",
    "nigs", "nigabro", "tinyniga", "SuperNiga", "HOLYNIGA", "gigaNyga", "MrN1663r", "BigN199a", "N166ER", "nupidor",
    "JaPidor", "LolP1dr", "TheAustrianArtist", "austrian_painter", "PintorAustriaco", "Uncle_Adolf", "Kitler88",
    "AdolfFitler", "XitIer", "Kristal_Nacht", "HateJews", "JewSlayer", "GasJews", "JEBAC_ZYDOW", "pedophile",
    "Pedofilo", "OsamaBin", "Al_Qaeda", "xChigga", "Nazista", "ZyklonB",
};
static const char *const ALLOWED[] = {
    "Mustafa69", "MustafaGS", "Mustafa_GS", "Mustafa Gamer", "mustafagamer", "Rafa96", "Vefa", "Safa", "Pakize",
    "Nigar", "Nigeria", "Nigerian", "Nigel", "Raccoon", "Tycoon", "Cocoon", "spicy", "Spice", "despicable",
    "Pakistan", "Fagundes", "Bigger", "Trigger", "Digger", "Knight", "Chinook", "Scunthorpe", "Cooper", "Ahmet35",
    "Emre_34", "Gökhan", "İbrahim", "Tobi", "Player", "NAME", "OLHOST", "Speedy", "", "Hakan1995", "Furkan1999",
    "Ozan_1996", "Can 1969", "Kaan1998", "Dani99", "Toni69", "Dani99GS", "Ozan1996GS", "Hakan1993TR", "Dani9912",
    "Strannik", "VanDyke", "Van Dyke", "Spider", "MR.SPIDER", "Shinigami", "Zuniga", "Vlado", "Vitaliba_Nox",
    "Grapes", "Trapezio", "Adolf", "Nazim", "Nazif", "Nygaard", "Mongol", "Churkin", "jacob88", "Jane8848",
    "Ahmet1448", "RapidRacer", "rapid racer", "CupidRacer", "Stupidrift", "StupidArmy", "TepidRide", "Hoonigan",
    "Hooniga", "Minigame", "Minigas", "Kniga", "Kunigas", "Niigaki", "NIGAMI", "Nygard", "TonyGamer",
    "Antony Gaming", "Brony_Gamer", "Higgins", "Higgs", "Austria", "AustrianGP", "Painter", "Artist", "Osama",
    "TopiDrift", "N1995", "Doran1994TR",
};

#define N(a) (int)(sizeof a / sizeof a[0])

int main(void){
    int fails = 0, checks = 0;
    for (int i = 0; i < N(BLOCKED); i++, checks++) if (!name_blocked(BLOCKED[i])){ printf("FAIL not refused: %s\n", BLOCKED[i]); fails++; }
    for (int i = 0; i < N(ALLOWED); i++, checks++) if (name_blocked(ALLOWED[i])){ printf("FAIL refused: %s\n", ALLOWED[i]); fails++; }
    /* a word of the whole list only as a part on its own */
    checks += 3;
    if (name_blocked("xfagx")){ printf("FAIL refused: xfagx\n"); fails++; }
    if (!name_blocked("x_fag_x")){ printf("FAIL not refused: x_fag_x\n"); fails++; }
    if (!name_blocked("xFagX")){ printf("FAIL not refused: xFagX\n"); fails++; }
    printf("names_unit: %d of %d checks failed\n", fails, checks);
    if (!fails) printf("names_unit: all %d checks passed\n", checks);
    return fails != 0;
}
