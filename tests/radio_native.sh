#!/bin/sh
# The music folder's tests (runtime/radio.c, radio_native.m): the decoder on synthesized WAV files, radio.c with
# the real decoder and a stubbed mixer, and radio.c's scenarios of the game's songs, in EU and NA addresses.
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/tests
FW="-framework Cocoa -framework AVFoundation -framework AudioToolbox"
clang -O1 -fobjc-arc -mmacosx-version-min=11.0 -Iruntime -Itests tests/radio_native_unit.m runtime/radio_native.m $FW -o out/tests/radio_native_unit
out/tests/radio_native_unit
clang -O1 -fobjc-arc -mmacosx-version-min=11.0 -Iruntime -Itests tests/radio_native_mixer.m runtime/radio_native.m $FW -o out/tests/radio_native_mixer
out/tests/radio_native_mixer
clang -O1 -DNFSU2_RADIO_TEST -Iruntime -Itests tests/radio_unit.c -o out/tests/radio_unit
out/tests/radio_unit | tail -1
clang -O1 -DNFSU2_RADIO_TEST -DNFS_EXE_NA=1 -include runtime/build_na.h -Iruntime -Itests tests/radio_unit.c -o out/tests/radio_unit_na
out/tests/radio_unit_na | tail -1
