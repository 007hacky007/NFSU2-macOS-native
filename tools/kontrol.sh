#!/bin/bash
# Hizli butunluk kontrolu: build(ler)i gorunmez ve sessiz bir Quick Race'te
# kosturur, kosu sonu raporundaki sayaclari denetler.  Bir degisiklikten sonra
# "oyun hala menuden yarisa gidiyor, ceviri / GPU / ses temiz mi" sorusunun
# tek komutluk cevabi (ISA ve fonksiyon testleri icin: ./run.sh test).
#
#   ./tools/kontrol.sh            iki build (out/nfsu2_boot, out/nfsu2_hd_boot)
#   ./tools/kontrol.sh orig|hd    tek build
#
# NFSU2_DATA: oyun klasoru ya da SPEED2.EXE (run.sh ile ayni).  Pencere hic
# gorunmez (NOFOCUS=2), ses kapali, ayarlar (~/.nfsu2_registry) kosudan sonra
# geri yuklenir, kayitlar gecici bir klasore gider (gercek kariyer kayitlarina
# dokunulmaz).  Bir build ~1.5 dk.  Cikis kodu: 0 = hepsi gecti.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2/SPEED2.EXE"
if [ -n "${NFSU2_DATA:-}" ]; then
  if [ -d "$NFSU2_DATA" ]; then EXE="$NFSU2_DATA/SPEED2.EXE"; else EXE="$NFSU2_DATA"; fi
fi
[ -f "$EXE" ] || { echo "SPEED2.EXE bulunamadi: $EXE"; exit 2; }
case "${1:-both}" in
  both) BUILDS="orig hd" ;; orig|hd) BUILDS="$1" ;;
  *) echo "kullanim: tools/kontrol.sh [orig|hd]"; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_kontrol.XXXXXX")"
REG="$HOME/.nfsu2_registry"
[ -f "$REG" ] && cp "$REG" "$TMP/registry.yedek"
geri_yukle(){ [ -f "$TMP/registry.yedek" ] && cp "$TMP/registry.yedek" "$REG"; }
trap geri_yukle EXIT

# Menulerden Quick Race'e (bkz. PROJECT.md / quick-race tarifi), 4700'den sonra gaz.
SEQ="1000:0x1C,1350:0x1C,1700:0x1C,2050:0x1C,2400:0x1C,2750:0x1C,3100:0x1C,3700:0x1C,4000:0x1C,4700:0xC8:2200"
Q=7000
HATA=0

kontrol(){   # $1 ad, $2 kosul (0/1), $3 ayrinti
  if [ "$2" = 1 ]; then printf "  GECTI  %-34s %s\n" "$1" "$3"
  else printf "  KALDI  %-34s %s\n" "$1" "$3"; HATA=1; fi
}
sayi(){ grep -a -E "$1" "$LOG" | tail -1 | sed -E "s|.*$2.*|\\1|"; }

for b in $BUILDS; do
  BIN="$ROOT/out/nfsu2_boot"; [ "$b" = hd ] && BIN="$ROOT/out/nfsu2_hd_boot"
  [ -x "$BIN" ] || { echo "== $b: $BIN yok (./build.sh && ./link.sh)"; HATA=1; continue; }
  LOG="$TMP/$b.log"; mkdir -p "$TMP/kayit_$b"
  echo "== $b ($(basename "$BIN"), $Q kare)"
  env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
    FIXMAT=1 FIXMAT_MODE=3 NOMOVIES=1 SNDSYNC=1 GPUVS=1 WINDOW=1 ALARM=0 \
    NOFOCUS=2 NOSOUND=1 NFSFULL=0 MOUSEAT=5,5 FSFAKE=300 \
    NFSU2_SAVEDIR="$TMP/kayit_$b" AUTOSEQ="$SEQ" QUITFRAMES=$Q GPUWIN=6000,6900 \
    "$BIN" "$EXE" > "$LOG" 2>&1
  rc=$?
  geri_yukle

  kontrol "kosu tamamlandi" "$([ $rc = 0 ] && grep -a -q "^  desteklenmeyen komut" "$LOG" && echo 1 || echo 0)" "cikis $rc"
  v=$(sayi "desteklenmeyen komut" ': ([0-9]+)'); kontrol "desteklenmeyen komut = 0" "$([ "${v:-x}" = 0 ] && echo 1 || echo 0)" "${v:-?}"
  v=$(sayi "dolayli cagri +cozulemedi" ': ([0-9]+)'); kontrol "cozulemeyen dolayli cagri = 0" "$([ "${v:-x}" = 0 ] && echo 1 || echo 0)" "${v:-?}"
  v=$(sayi "\[matris\]" 'bozuk=([0-9]+).*'); kontrol "bozuk matris = 0" "$([ "${v:-x}" = 0 ] && echo 1 || echo 0)" "${v:-?}"
  v=$(sayi "komut tamponu hatasi: [0-9]+ kare" 'hatasi: ([0-9]+) kare'); kontrol "GPU komut tamponu hatasi = 0" "$([ "${v:-x}" = 0 ] && echo 1 || echo 0)" "${v:-?}"
  v=$(sayi "tanesi EKSIK" ', ([0-9]+) tanesi EKSIK'); kontrol "eksik mip seviyesi = 0" "$([ "${v:-x}" = 0 ] && echo 1 || echo 0)" "${v:-?}"
  v=$(grep -a -E "^ +vs[0-9]+: surum" "$LOG" | grep -a -v -c ", 0 bilinmeyen"); kontrol "kose gölgelendiricisinde bilinmeyen = 0" "$([ "$v" = 0 ] && echo 1 || echo 0)" "$v gölgelendirici"
  v=$(sayi "imlec asimi" ': ([0-9]+) geri'); kontrol "ses: imlec asimi = 0" "$([ "${v:-0}" = 0 ] && echo 1 || echo 0)" "${v:-(ses kapali)}"
  # yarisa gercekten girildi mi: olcum penceresinde kare basina cizim (menu ~475, yaris ~900+)
  v=$(sayi "cizim cagrisi: [0-9]+/kare" 'cizim cagrisi: ([0-9]+)/kare'); kontrol "yarisa girildi (cizim/kare > 700)" "$([ "${v:-0}" -gt 700 ] && echo 1 || echo 0)" "${v:-?}"
  if [ "$b" = hd ]; then
    v=$(sayi "\[HD\] isin izleme: [0-9]+ kare" 'izleme: ([0-9]+) kare'); kontrol "HD: isin izleme calisti" "$([ "${v:-0}" -gt 500 ] && echo 1 || echo 0)" "${v:-0} kare"
    v=$(sayi "\[HD\] MSAA ekleri" 'ongoru tutmayan ([0-9]+).*'); kontrol "HD: belleksiz MSAA ongorusu tuttu" "$([ "${v:-x}" = 0 ] && echo 1 || echo 0)" "${v:-?}"
    v=$(sayi "\[HD\] ayri G gecisi" 'ACIK, ([0-9]+) gecis.*'); kontrol "HD: ayri G gecisi calisti" "$([ "${v:-0}" -gt 500 ] && echo 1 || echo 0)" "${v:-0} gecis"
  fi
done
echo
if [ $HATA = 0 ]; then echo "SONUC: hepsi gecti  (kayitlar: $TMP)"; else echo "SONUC: KALAN VAR  (kayitlar: $TMP)"; fi
exit $HATA
