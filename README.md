# CableDeX 0.3 — USB desktop and sharing

A native Apple silicon Mac app derived from dex-for-mac. Download **CableDeX-AppleSilicon.zip** from the [0.3.0 release](https://github.com/horse0910/CableDex/releases/tag/v0.3.0), unzip it, and open **CableDeX.app**. Requires macOS 13+. Locally ad-hoc signed; not Apple-notarized. Bundled tools run offline without Homebrew, Wi-Fi, an account, or a runtime download.

## Connect

1. Enable USB debugging on your Galaxy and connect a USB-C data cable directly to the Mac.
2. Unlock the phone. Click **Find phone**, accept the phone's debugging prompt, then click Find phone again.
3. Choose **Desktop** for a separate workspace, or **Phone screen** for mirroring, and click **Connect display**.

Defaults: **2560×1440, H.264, 60 fps cap, 30 Mbps, zero added video buffer**. HEVC, resolution, density, bitrate, frame rate, and full screen remain selectable. These settings affect the virtual display or stream; they do not change the Mac's resolution/scaling.

## USB sharing

The requested features are enabled on upgrade. Their checkboxes apply to the next display session and remain saved afterward.

- **Play phone audio on this Mac:** Android output capture, raw stereo PCM over USB, with a 50 ms audio buffer. Video uses its own pipeline and zero added video buffer. Some Android apps block audio capture. Microphone capture is not exposed and the client forces the source to output.
- **Share text clipboard:** scrcpy text clipboard synchronization and copy/paste shortcuts in the display window. This can copy whatever text you copy during the session, including sensitive text. Turn the switch off before connecting when unwanted. Clipboard images/files are not supported.
- **Allow selected file transfers:** **Send files…** selects regular Mac files and copies them into a new `Download/CableDeX/Transfer-<UUID>` folder. **Browse phone…** lists shared storage; select a file and choose its Mac save location. No automatic folder sync, recursive transfer, or deletion interface is provided. File transfers can run without opening the display once the USB phone is discovered.
- **Cancel transfer** stops the active operation. Received files are staged and published only after success. An interrupted send may leave a hidden partial file in its new phone folder. Transfers share USB bandwidth with video, so large copies can affect responsiveness.

Direct file drops into the viewer, APK installation, and recording stay blocked. Sending an APK as an ordinary selected file does not install it. View-only mode pauses clipboard and file transfer as well as device input; audio can remain on. Settings cannot change while a transfer or display session is active.

## Phone display off and controls

Select **Turn phone display off while connected** before connecting. This sends scrcpy's panel-power command and keeps the session active without changing persistent screen timeout, stay-awake, or lock preferences.

Panel off differs from locking Android. Use this option instead of the physical power button. The phone must first be unlocked; lock/sleep may suspend the desktop. The app never bypasses authentication. Continued streaming with the S24 Ultra panel off still needs live testing.

Keyboard/mouse control is on by default. Type, scroll, click, and drag in the display window. Right-click is forwarded as a right-click; Command+B sends Android Back. Live verification of these controls on the phone is pending.

## Access and local data

Android has no mirroring-only ADB authorization. CableDeX restricts its own behavior, but cannot narrow the phone's debugging grant or prevent another program under your Mac account from using its ADB keys. Revoke authorization or disable debugging when no longer needed.

This implementation copies a 733,930-byte temporary scrcpy server to `/data/local/tmp/scrcpy-server.jar` and executes it as Android's shell user. It is not installed as an APK; scrcpy handles cleanup. Desktop mode creates a temporary secondary display and optionally requests freeform mode there, then clears that override on normal disconnect. Exact One UI 9 behavior still needs live verification.

Only physical USB transports are accepted and revalidated. ADB uses a private user-owned Unix socket; mDNS, wireless auto-connect, and emulator network discovery are disabled. Local loopback sockets between scrcpy and ADB remain on the Mac. The app has no telemetry, cloud upload, contacts/messages query, account, general device-shell UI, or microphone feature. Existing phone wireless-debugging preferences are not changed.

ADB uses standard `~/.android` authorization keys. The bounded session log is `~/Library/Application Support/CableDeX/session.log` in a mode-700 folder with a mode-600 file; private bridge diagnostics are under `/private/tmp/cabledex-<uid>/`. No shell-profile edits or administrator installation are needed.

## Timing and verification

**Mac pipeline** measures completed packet arrival through decode/queue/render submission. It excludes phone rendering/encoding, USB transit, input transit, and physical panel scanout. It is not end-to-end latency. Capture FPS can fall to zero on a static desktop.

`bash scripts/test.sh` passed **133 offline checks**: 49 core, 19 mock-session, 40 file-transfer, and 25 compiled backend-policy checks. `bash scripts/test-audio.sh` decoded PCM and verified the Mac's CoreAudio output consumes a short silent buffer. No phone was used for these tests. Live audio, clipboard, file transfer, controls, panel-off streaming, and latency remain unverified for version 0.3.

`bash scripts/build.sh` builds the wrapper offline with Apple's Command Line Tools, checks pinned hashes, signs/verifies the bundle, and creates the ZIP/checksum. To rebuild the custom client, use `scripts/build-backend.sh`. Pinned source archives, reviewed patch, policy header, and local build tools are retained under Backend and .build-tools. The build cache is `/private/tmp/cabledex-backend-build-20261027`.

See SAFETY.md, VALIDATION.md, and THIRD_PARTY.md for scope and provenance.

## Build from this repository

The checked-in `Vendor` executables are the same pinned artifacts used by the release. To build the native app on Apple silicon with Apple's Command Line Tools installed:

```sh
bash scripts/test.sh
bash scripts/build.sh
```

Backend-policy tests require the backend build cache; without it, the script reports that portion as skipped. The other core/session/file checks use local fixtures and do not access a real phone.

To rebuild the backend too, use Python 3.12 or newer and the local build tools:

```sh
python3.12 -m venv .build-tools
.build-tools/bin/python -m pip install meson==1.12.1 ninja==1.13.2 cmake==4.4.4
bash scripts/build-backend.sh
```

Installing build tools needs an internet connection. Source archives in `Backend/archives` include complete SDL, FFmpeg, patched scrcpy, and pkgconf sources; their hashes are verified before extraction. Published snapshots omit nested Git metadata and verify against `Backend/scrcpy-SNAPSHOT.json`. Local edits to that verified snapshot require an intentional manifest update before rebuilding. Replacing `Vendor/scrcpy` with a rebuilt client also requires updating its expected hash in `scripts/build.sh` and `Resources/ToolManifest.json`.

The complete source snapshot and release checksums are also attached to the release. Original attribution is retained in LICENSE, Upstream, and THIRD_PARTY.md. Diagnostics, debugging keys, personal files, and local build caches are excluded.
