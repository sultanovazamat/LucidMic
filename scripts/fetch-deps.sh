#!/bin/sh
# Downloads the denoiser runtime and model into build/deps (not committed):
#   sherpa-onnx v1.13.8 no-TTS C API + ONNX Runtime (Apache-2.0 / MIT), DPDFNet2 model (Apache-2.0, Ceva).
set -eu
cd "$(dirname "$0")/.."
DEPS=build/deps
SHERPA_SHA=91b96512c4fa1960f8a9ed5360a6c8dda53a4b5015d0590244f14086a234557a
SHERPA_LIB_SHA=ae729669633008692c670d4e4c942db7ea5bdc38abc2f479516062d48849e9d1
ONNX_LIB_SHA=3567d114f7299d559993e536d605a6f46d7bc9d2542004accc80ee9bf5457f0b
MODEL_SHA=0b399f8a58dc4d70d8cd97541f5c39869406145193b957d00a03b66070944928
check_runtime() {
    printf '%s  %s\n' "$SHERPA_LIB_SHA" "$DEPS/sherpa/lib/libsherpa-onnx-c-api.dylib" \
        "$ONNX_LIB_SHA" "$DEPS/sherpa/lib/libonnxruntime.dylib" | shasum -a 256 -c -
}
mkdir -p "$DEPS"
if [ ! -f "$DEPS/sherpa/.verified-$SHERPA_SHA" ] || \
    [ ! -f "$DEPS/sherpa/include/sherpa-onnx/c-api/c-api.h" ] || \
    ! check_runtime >/dev/null 2>&1; then
    curl --fail --location --silent --show-error --retry 3 -o "$DEPS/sherpa.tar.bz2.part" \
        https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts.tar.bz2
    printf '%s  %s\n' "$SHERPA_SHA" "$DEPS/sherpa.tar.bz2.part" | shasum -a 256 -c -
    mv "$DEPS/sherpa.tar.bz2.part" "$DEPS/sherpa.tar.bz2"
    tar xjf "$DEPS/sherpa.tar.bz2" -C "$DEPS"
    rm -rf "$DEPS/sherpa" && mv "$DEPS/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts" "$DEPS/sherpa"
    touch "$DEPS/sherpa/.verified-$SHERPA_SHA"
    rm "$DEPS/sherpa.tar.bz2"
fi
check_runtime
if [ ! -f "$DEPS/dpdfnet2_48khz_hr.onnx" ]; then
    curl --fail --location --silent --show-error --retry 3 -o "$DEPS/dpdfnet2_48khz_hr.onnx.part" \
        https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2_48khz_hr.onnx
    printf '%s  %s\n' "$MODEL_SHA" "$DEPS/dpdfnet2_48khz_hr.onnx.part" | shasum -a 256 -c -
    mv "$DEPS/dpdfnet2_48khz_hr.onnx.part" "$DEPS/dpdfnet2_48khz_hr.onnx"
fi
printf '%s  %s\n' "$MODEL_SHA" "$DEPS/dpdfnet2_48khz_hr.onnx" | shasum -a 256 -c -
echo "deps ready in $DEPS"
