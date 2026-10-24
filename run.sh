#!/bin/bash
# NFSU2 native ARM64 portunu calistir
ROOT="$(cd "$(dirname "$0")" && pwd)"
# NFSU2_DATA: oyun klasoru (icinde SPEED2.EXE) ya da dogrudan SPEED2.EXE yolu.
# Verilmezse depo kokundeki varsayilan klasor kullanilir.
EXE="$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2/SPEED2.EXE"
if [ -n "$NFSU2_DATA" ]; then
  if [ -d "$NFSU2_DATA" ]; then EXE="$NFSU2_DATA/SPEED2.EXE"; else EXE="$NFSU2_DATA"; fi
fi
[ -f "$EXE" ] || { echo "SPEED2.EXE bulunamadi: $EXE"; exit 1; }
# IKI BUILD (bkz. link.sh):
#   ./run.sh [mod]          orijinal  (out/nfsu2_boot)
#   NFSHD=1 ./run.sh [mod]  HD        (out/nfsu2_hd_boot) -- grafik iyilestirmeleri
#   ./run.sh hd | hd1080p   HD'nin kisayollari
# HD ayarlari (yalnizca HD build okur): HDREFL=0 (yansima iyilestirmesi kapali),
#   HD_ROAD (yol yansimasi olcegi; varsayilan isin izleme acikken 1/3, kapaliyken 0.5),
#   HD_BLUR=0.5, HD_MIRROR=1024, HD_CUBE=512,
#   HD_MSAA (varsayilan otomatik: 1440 satir ve ustu 2x, alti 4x; 1 = kapali),
#   HD_SSR=1 (0 kapali), HD_SSR_CAR=1 (araba boyasi), HD_RT=1 (isin izlemeli yansima; 0 = SSR),
#   HD_GSEP=1 (G-tamponu ayri tek ornekli geciste), HD_MBFIX=1 (hareket bulanikliginda
#   sahne cok ornekli devam eder), HD_RT_FAR / HD_RT_BMIN (isin sinirlari; varsayilan kapali).
#   Ayrinti: runtime/enhance.c, runtime/metal.m (ayni adli bolumler)
# Oyun icinde Cmd+Shift+D: o karenin PNG'si + cizim listesi (~/Library/Logs/NFSU2/
#   ya da PERFLOG dizini).  Oynarken olcum kaydi: tools/oturum.sh [hd].
MODE="${1:-window}"
case "$MODE" in
  hd)      NFSHD=1; MODE=window ;;
  hd1080p) NFSHD=1; MODE=1080p ;;
esac
BIN="$ROOT/out/nfsu2_boot"
[ "${NFSHD:-0}" = 1 ] && BIN="$ROOT/out/nfsu2_hd_boot"
[ -x "$BIN" ] || { echo "once derleyin: ./build.sh && ./link.sh  ($BIN yok)"; exit 1; }
[ "${NFSHD:-0}" = 1 ] && echo "build: HD (grafik iyilestirmeleri acik)" || echo "build: orijinal"

# --- gecici gerekli ayarlar (kok nedenleri hala acik) ---
# FIXMAT   : oyunun on yuz WorldViewProj matrisi bozuk geliyor (yalnizca
#            2. ve 3. satirlari yazili, 0-1 sifir) -> her kose (1,1)'e
#            cokuyor.  MODE=3 dogru olan birim matrisi enjekte eder;
#            ham konumlar zaten kirpma uzayinda.
# NOMOVIES : VP6 video kod cozucusu yok; video dosyalari yok sayilmazsa
#            oyun ilk videoda sonsuza kadar bekliyor.
# Tani amacli sentetik giris/zorlama degiskenleri kabuktan sizmasin:
# eski bir "export AUTOKEY=..." oyunu kendiliginden tikliyor gosteriyordu.
unset AUTOKEY AUTOCLICK FORCESWITCH FETICK GAMELOG DUMPFRAME BOOTFLOW \
      DATADIFF VSKDUMP OWNERSCAN PARAMNAME PDLIST WATCHVSK WATCHADDR \
      MPROT_HARD MPROT_ANY MPROT_PERSIST PRESENTBT VSKBT GLYPHDUMP DRAWDUMP \
      AUTOSEQ AUTOTEXT GILLOG SNDSTAT SNDGAP SNDLOG \
      READLOG GPUVSLOG GPUVSDUMP GPUVSMASK NOVS NOPACE PACE60 TESTFILL \
      SKIPDRAW CLEARCOL MIPOFF DRAWV SLIVER PSDUMP DUMPMIP DUMPTEX SMPLOG LOCKLOG RTLOG \
      DRAWSUM PSISO SKIPPS PSINFO BLITLOG SNDCSV SNDDUMP SNDBACKEND \
      FPSCSV AUTOKEYSTOP VCLOCK VCLOCK_MAXD DECLLOG CULLWIND RSLOG NOFOG BLITQUAD RESSCAN ASPFIX ASPLOG PSHIST MIPLIN NOANISO LODMAX \
      RTIDLOG DRAWVPS ZSHARELOG XFORMAT CAMLOG HD_SSR_DEBUG VIEWLOG HD_RTPROBE HD_RTPROBE2 HD_RT_STAGE HD_RT_NOTEX HD_RT_PLAIN HD_RT_ONLYCX HD_RT_SLOWBUILD HD_RT_LOG HD_RT_DUMPTAB HD_RT_STRESS HD_COMP HD_MSLAZY HD_REORDER HD_RT_AB HD_RT_FIX HD_RT_POISON FORCERAIN FORCETOD FORCETOD_STATE GPUWIN PASSPROF PASSPROF_MODE GPUVSDUMP \
      SNDMUTE YAKALAKARE DRAWLIST NODRAW LIMFREE ABTEST PASSPROF_CSV HD_MBLOG HD_RT_DLOG HD_RT_ONLY HD_RTPROBE2_HER

export FIXMAT="${FIXMAT:-1}"
export NOMOVIES="${NOMOVIES:-1}"
export FIXMAT_MODE="${FIXMAT_MODE:-3}"
# SNDSYNC : oynatma hizini oyunun sanal saatinin gercek zamana oranina bagla.
#           Saat artik gercek gecen sureyle ilerledigi icin oran normalde 1.000;
#           yalnizca uzun bir takilmada kisa sure duser (yazilmamis bolgeyi
#           calmamak icin).  0 = hep gercek zamanda cal.
# SNDPLL  : eski yazma-imleci servosu (varsayilan KAPALI).  Oyun yazdigi yeri
#           bizim oynatma imlecimize gore sectigi icin servo hatayi kapatamiyor,
#           muzigi 40-50 sn %3 yavas/hizli caldiriyordu (bkz. runtime/audio.m).
export SNDSYNC="${SNDSYNC:-1}"
# GPUVS : kose gölgelendiricisini GPU'da calistir (oyunun kendi bytecode'u
#         MSL'ye cevrilir).  Olculdu: cizim yolu 34.6 sn -> 2.2 sn,
#         kose verimi 2.4 -> 90 M/sn.  Cevrilemeyen gölgelendirici
#         otomatik olarak CPU yorumlayicisina duser.
#         GPUVS=0 ile eski (CPU) yola donulur.
export GPUVS="${GPUVS:-1}"

# NOT: eskiden burada "on yuz UG_LS_Splash.fng'de takiliyor, FORCESWITCH=3
# gerekiyor" yaziyordu.  Artik GECERLI DEGIL: FPUSH duzeltmesinden sonra
# oyun kendiliginden baslik ekranina gelip "Press Enter Key" ile bekliyor --
# orijinal davranisin ta kendisi.  FORCESWITCH=3 yalnizca menuye Enter'siz
# atlamak icin (olcum/tani) duruyor.
# NFSRES: oyunun kendi cozunurluk tablosu 6 satir ve tamami 4:3 -- menuden
# 1080p secilemiyor.  Bu degisken cihazi istenen boyutta acar, geometriyi
# Hor+ genis ekrana duzeltir ve arayuzu dairesel tutar (HUDFIX=0 ile kapatilir).
#   NFSRES=1920x1080 ./run.sh      ya da     ./run.sh 1080p
export NFSRES="${NFSRES:-}"
# NFSNATIVE: Retina ekranda oyunun sectigi cozunurlugu (menude en fazla
#   1280x960) ORANI KORUYARAK ekranin gercek piksel sayisina cikarir (14"
#   MacBook Pro'da 2448x1836).  Eskiden 1280x960'lik yuzey pencereye ~2 kat
#   buyutulup bulaniklasiyordu.  Varsayilan ACIK.  NFSNATIVE=0 kapatir:
#   goruntu yine 1:1 piksel olur ama pencere yarim boyutta acilir.
#   NFSRES verilirse o kazanir.
# NFSMAXPIX: native olcegin ust siniri, piksel sayisi (varsayilan 6000000;
#   5K/6K ekranlarda kare butcesini korumak icin).

# Cift tiklanabilir .app icin:  ./pack.sh  (bkz. out/NFSU2.app)

if [ "$MODE" = "1080p" ]; then MODE=window; export NFSRES="${NFSRES:-1920x1080}"; fi
[ -n "$NFSRES" ] && echo "cozunurluk: $NFSRES (genis ekran duzeltmesi acik)"
case "$MODE" in
  window)   echo "pencereli mod (kapatmak icin pencereyi kapat ya da Ctrl-C)"
            WINDOW=1 ALARM="${ALARM:-0}" exec "$BIN" "$EXE" ;;
  headless) echo "penceresiz mod, ${ALARM:-60} sn"
            ALARM="${ALARM:-60}" exec "$BIN" "$EXE" ;;
  profile)  echo "ornekleyici profil"
            SAMPLE=1 ALARM="${ALARM:-30}" exec "$BIN" "$EXE" ;;
  trace)    echo "D3D9 cagri izi"
            COMTRACE=1 ALARM="${ALARM:-20}" exec "$BIN" "$EXE" ;;
  test)     "$ROOT/out/isatest" && "$ROOT/out/nfsu2_all" "$EXE" ;;
  *)        echo "kullanim: [NFSHD=1] ./run.sh [window|1080p|hd|hd1080p|headless|profile|trace|test]"; exit 1 ;;
esac
