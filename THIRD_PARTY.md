# Provenance — CableDeX 0.3

## Original wrapper

Derived from https://github.com/yongtingzhengcn-web/dex-for-mac at commit `2903e2fbb93edc38af5dbb6a7240152fb748ecf5`. The original Swift source and MIT license remain in Upstream; the icon is from the same commit. No original wireless or installation script is exposed by the app.

## Restricted scrcpy client

The client is now compiled locally from official scrcpy v5.0.1, commit `a60891aea193d92e7e5c3942700eca63f9d19a5f`, with the reviewed USB-only sharing patch in Backend/cabledex.patch and policy header in Backend/CableDeXPolicy.h.

Restricted client SHA-256: `f4c205df0320209fe8fc836b8fb8bbe669703d9fab586e6038da45495945a17e`.

It is a modified build, not the original upstream release binary. Audio output and clipboard handlers follow explicit per-launch settings. Viewer file drops, APK installation, microphone capture, recording, and network-device connection paths are blocked. Selected files use the native wrapper’s reviewed transfer implementation. Packet-receive timestamps support a clearly labeled Mac-only pipeline counter. The original scrcpy license is retained in Vendor/LICENSE and bundled in the app. Upstream: https://github.com/Genymobile/scrcpy/tree/v5.0.1 (Apache 2.0).

## Unmodified runtime components

The ADB binary and Android server remain byte-identical to the official scrcpy 5.0.1 Apple silicon release:

- Official archive SHA-256: `33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b`.
- ADB 37.0.1: `1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b`.
- Android server: `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`.
- Source release: https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1.

Resources/ToolManifest.json records the current app's exact runtime hashes; the app checks them before scanning or starting. A checksum proves equality to a selected artifact, not an independent malware certification.

## Static client dependencies and source availability

- SDL 3.4.18, zlib license, official source archive SHA-256 `c4b08b950bd29d83caae0ab8d884298d27046a9d30700fb42841c50992665c90`. Source: https://github.com/libsdl-org/SDL/tree/release-3.4.18. License copied to Vendor/SDL-LICENSE.txt and included in the app. CoreAudio output is enabled. Camera/joystick/haptic/sensor support was disabled in this SDL build.
- FFmpeg 9.0.2, LGPL build with no GPL/nonfree options; source archive SHA-256 `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`. Source: https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz. License copied to Vendor/FFmpeg-COPYING.LGPLv2.1 and included in the app. Only H.264/HEVC/PNG/PCM-S16LE decoding and required supporting libraries are configured; FFmpeg network support and recording muxers were disabled.
- Both complete source archives are retained in Backend/archives. The modified scrcpy source, patch, and build scripts are retained in Backend and scripts. In this publication, complete scrcpy/pkgconf sources are pinned archives under Backend/archives and are verified/extracted by scripts/prepare-backend.py; nested Git metadata is omitted. The client can be rebuilt/relinked using these sources and the local build tools.
- pkgconf 2.5.1, commit `4fc570f91d9d8d843ab32d2198a5c064538d8ffd`, is used only at build time, not bundled as a runtime tool. Its source/license are retained in Backend/pkgconf. Meson/Ninja/CMake are isolated build-time tools in .build-tools.

This is a locally built personal-use artifact. It is not affiliated with Samsung, Apple, Google, Genymobile, or the original wrapper's author. Nothing has been uploaded or publicly released.
