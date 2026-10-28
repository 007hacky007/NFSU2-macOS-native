#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/tests
clang -O1 -fobjc-arc -mmacosx-version-min=11.0 -Iruntime -Itests tests/radio_native_unit.m runtime/radio_native.m -framework Foundation -framework AVFoundation -framework AudioToolbox -o out/tests/radio_native_unit
out/tests/radio_native_unit
clang -O1 -fobjc-arc -DNFSU2_NATIVE_RADIO -mmacosx-version-min=11.0 -Iruntime -Itests tests/radio_native_mixer.m runtime/radio_native.m -framework Foundation -framework AVFoundation -framework AudioToolbox -o out/tests/radio_native_mixer
out/tests/radio_native_mixer
clang -O1 -DNFSU2_RADIO_TEST -Iruntime -Itests tests/radio_unit.c -o out/tests/radio_unit
out/tests/radio_unit
