#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_BUILD=/private/tmp/cabledex-backend-build-20261027
DEPS_PREFIX="$BACKEND_BUILD/deps"
export PATH="$PROJECT_DIR/.build-tools/bin:$DEPS_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MACOSX_DEPLOYMENT_TARGET=13.0
export PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig"
mkdir -p "$DEPS_PREFIX"
python3 "$PROJECT_DIR/scripts/prepare-backend.py"
python3 "$PROJECT_DIR/scripts/patch-backend.py"

if [[ ! -x "$DEPS_PREFIX/bin/pkgconf" ]]; then
  meson setup "$BACKEND_BUILD/pkgconf-build" "$PROJECT_DIR/Backend/pkgconf" \
    --prefix="$DEPS_PREFIX" --libdir=lib --buildtype=release --default-library=static -Dtests=disabled
  ninja -C "$BACKEND_BUILD/pkgconf-build" install
fi
export PKG_CONFIG="$DEPS_PREFIX/bin/pkgconf"

if [[ ! -f "$DEPS_PREFIX/SDL_AUDIO_ENABLED" ]]; then
  cmake -S "$BACKEND_BUILD/SDL-release-3.4.18" -B "$BACKEND_BUILD/sdl-build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_BUILD_TYPE=Release \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF \
    -DSDL_AUDIO=ON -DSDL_CAMERA=OFF -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_SENSOR=OFF
  cmake --build "$BACKEND_BUILD/sdl-build" -j8
  cmake --install "$BACKEND_BUILD/sdl-build"
  touch "$DEPS_PREFIX/SDL_AUDIO_ENABLED"
fi

if [[ ! -f "$DEPS_PREFIX/FFMPEG_AUDIO_ENABLED" ]]; then
  mkdir -p "$BACKEND_BUILD/ffmpeg-build"
  (
    cd "$BACKEND_BUILD/ffmpeg-build"
    "$BACKEND_BUILD/ffmpeg-9.0.2/configure" --prefix="$DEPS_PREFIX" --pkg-config="$PKG_CONFIG" \
      --pkg-config-flags=--static --cc=/usr/bin/clang --arch=aarch64 --target-os=darwin \
      --extra-cflags='-O2 -fPIC -mmacosx-version-min=13.0' --extra-ldflags=-mmacosx-version-min=13.0 \
      --disable-programs --disable-doc --disable-autodetect --disable-network --disable-everything \
      --disable-avdevice --disable-avfilter --disable-swscale --enable-swresample \
      --enable-decoder=h264,hevc,png,pcm_s16le --enable-parser=png --enable-protocol=file --enable-demuxer=image2 \
      --enable-zlib --enable-videotoolbox --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox \
      --enable-static --disable-shared --enable-pthreads
    make -j8
    make install
    touch "$DEPS_PREFIX/FFMPEG_AUDIO_ENABLED"
  )
fi

if [[ ! -f "$BACKEND_BUILD/client-v03-build/build.ninja" ]]; then
meson setup "$BACKEND_BUILD/client-v03-build" "$PROJECT_DIR/Backend/scrcpy" \
  --buildtype=release -Dcompile_server=false -Dportable=true -Dstatic=true -Dusb=false -Dv4l2=false \
  -Dc_args="-I$DEPS_PREFIX/include -mmacosx-version-min=13.0" \
  -Dc_link_args="-L$DEPS_PREFIX/lib -mmacosx-version-min=13.0"
fi
ninja -C "$BACKEND_BUILD/client-v03-build"
printf 'Restricted backend: %s\n' "$BACKEND_BUILD/client-v03-build/app/scrcpy"
