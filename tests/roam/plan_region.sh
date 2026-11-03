# tests/roam/plan.sh plan for tests/scripts/roam_region_cars.txt: three
# stand-in friends near the prologue's free-roam start, in a Civic, an RSX
# and (20 s later, when a stuck car loader would keep it out) a 240SX.
( fp 0 --name Fp0 --stock CIVIC --circle 1700,-870,24.1,6,6 --seconds 120 ) &
( sleep 4; fp 1 --name Fp1 --stock RSX --circle 1710,-870,24.1,6,6 --seconds 120 ) &
( sleep 20; fp 2 --name Fp2 --stock 240SX --circle 1720,-870,24.1,6,6 --seconds 100 ) &
