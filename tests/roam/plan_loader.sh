# tests/roam/plan.sh plan for tests/scripts/roam_loader_overlap.txt: eight
# stand-in friends around the prologue's free-roam start, each changing to
# another stock car every 6 to 9 s for 10 minutes, so the game keeps loading
# their rides (the car loader busy) while the script reads part animations.
L=CIVIC,RX8,MUSTANGGT,FOCUS,350Z,ECLIPSE,G35,SKYLINE,240SX,TIBURON,RSX,GTO,COROLLA,MIATA,SUPRA,HUMMER
k=0
for x in 1700 1710 1720 1730 1740 1750 1760 1770; do
  ( sleep $k; fp $k --name "Fp$k" --stock CIVIC --looks "$L" --look-every $((6 + k % 4)) \
        --circle $x,-870,24.1,6,6 --seconds 600 ) &
  k=$((k + 1))
done
