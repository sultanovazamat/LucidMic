#!/bin/sh
# Downloads the denoiser runtime and model into build/deps (not committed):
#   sherpa-onnx v1.13.8 C API + ONNX Runtime (Apache-2.0 / MIT), DPDFNet2 48 kHz model (Apache-2.0, Ceva).
set -eu
cd "$(dirname "$0")/.."
DEPS=build/deps
SHERPA_SHA=b10e5c7e2c30ea03de9c442655d14860d9edc475c6251d58a8f5f06e913a1d56
MODEL_SHA=0b399f8a58dc4d70d8cd97541f5c39869406145193b957d00a03b66070944928
mkdir -p "$DEPS"
if [ ! -f "$DEPS/sherpa/.verified-$SHERPA_SHA" ] || \
    [ ! -f "$DEPS/sherpa/lib/libsherpa-onnx-c-api.dylib" ] || \
    [ ! -f "$DEPS/sherpa/lib/libonnxruntime.dylib" ]; then
    curl --fail --location --silent --show-error --retry 3 -o "$DEPS/sherpa.tar.bz2.part" \
        https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared.tar.bz2
    printf '%s  %s\n' "$SHERPA_SHA" "$DEPS/sherpa.tar.bz2.part" | shasum -a 256 -c -
    mv "$DEPS/sherpa.tar.bz2.part" "$DEPS/sherpa.tar.bz2"
    tar xjf "$DEPS/sherpa.tar.bz2" -C "$DEPS"
    rm -rf "$DEPS/sherpa" && mv "$DEPS/sherpa-onnx-v1.13.8-osx-arm64-shared" "$DEPS/sherpa"
    touch "$DEPS/sherpa/.verified-$SHERPA_SHA"
    rm "$DEPS/sherpa.tar.bz2"
fi
if [ ! -f "$DEPS/dpdfnet2_48khz_hr.onnx" ]; then
    curl --fail --location --silent --show-error --retry 3 -o "$DEPS/dpdfnet2_48khz_hr.onnx.part" \
        https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2_48khz_hr.onnx
    printf '%s  %s\n' "$MODEL_SHA" "$DEPS/dpdfnet2_48khz_hr.onnx.part" | shasum -a 256 -c -
    mv "$DEPS/dpdfnet2_48khz_hr.onnx.part" "$DEPS/dpdfnet2_48khz_hr.onnx"
fi
printf '%s  %s\n' "$MODEL_SHA" "$DEPS/dpdfnet2_48khz_hr.onnx" | shasum -a 256 -c -
echo "deps ready in $DEPS"
