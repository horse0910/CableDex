# CableDeX 0.3 validation — 27 October 2026

## Passed offline

- **49 core checks:** physical USB filtering, exact device selection, enabled sharing upgrade and persistent opt-outs, output/raw-PCM settings, view-only clipboard gate, panel-off/keep-active without persistent stay-awake, VideoToolbox startup parsing, timing parsing, bounded output, timeout/cancellation, integrity and display safeguards.
- **19 mock-session checks:** incremental startup events, secondary-display windowing, FPS/Mac timing propagation, cleanup, mirror mode, encoder error, preflight cancellation, and private bridge shutdown.
- **40 transfer checks using a local fake phone:** actual shell-quoting round trip, shared-storage boundaries, control/traversal rejection, exact binary round trip with Unicode/quote/metacharacter names, directory listing, private destination permissions, explicit replacement, symlink/folder/duplicate rejection, changed-transport rejection, cancellation cleanup, transfer switches, serialization, and controller completion state.
- **25 compiled backend-policy checks:** input/display allowlist, clipboard default-off/explicit-on/off gates, audio gate, blocked unknown/app/file/UHID/rotation messages, and raw push limited to the verified temporary server.
- **Mac audio output smoke test:** FFmpeg decoded 4,800 stereo PCM samples. SDL's CoreAudio backend consumed 48,000 silent bytes through the default playback device; zero remained after 500 ms. No microphone was opened and no phone was used. The restricted execution sandbox initially could not see a default audio device; the normal CoreAudio execution context passed.
- The client compiled from pinned scrcpy 5.0.1, SDL 3.4.18, and FFmpeg 9.0.2 sources with VideoToolbox and output audio enabled. Reviewed patch replay exactly matched the modified source files. The shared policy header matches the compiled source copy.

Total automated core/session/transfer/policy checks: **133 passed**. Mock-phone success does not establish Samsung firmware behavior.

## Packaging and UI

The app and ZIP use an ad-hoc signature and pinned hashes for ADB, the Android server, and the modified client. The wrapper targets Apple silicon macOS 13+. These checks are not notarization or malware certification. Final UI launch status is recorded in `build/BUILD-INFO.json`. Version 0.3 was opened with user approval. Its audio, clipboard, and selected-file switches appeared enabled, toggled off and back on, and view-only disabled clipboard/file/panel controls. Find phone returned no USB phone; Connect, Send files, and Browse phone remained disabled. The app was left open with requested sharing, keyboard/mouse, and panel-off preferences enabled.

Version 0.2 previously launched with user approval and correctly showed no phone, disabled Connect, and disabled panel-off control in view-only mode. Private ADB server metadata reported native USB, mDNS disabled, and version 37.0.1. These earlier observations do not verify version 0.3 phone features.

## Earlier phone evidence

Version 0.1 logs identified SM-S928B / Android 17, created a 2560×1440 desktop, accepted the per-display freeform request, and used Metal + VideoToolbox. Some H.264 samples reached approximately 60 fps; HEVC samples were generally lower under different workloads. Those logs are not a controlled codec or latency comparison.

The old status parser missed `Texture (VideoToolbox):`; current tests cover the corrected hardware-decoder startup parser.

## Deferred by the user

The user chose offline tests while the phone was disconnected. Version 0.3 still needs:

- S24 Ultra mouse clicks, right-click, drag, scroll, typing and view-only checks.
- Clipboard text transfer in both directions, with sharing on and off.
- Selected file send/receive on actual Android shared storage, cancellation, unplug/reconnect.
- Audio from an Android app that permits output capture; actual A/V offset and phone audio routing.
- Continued desktop streaming with the phone panel off; behavior after physical lock/sleep.
- Sustained capture/thermals and matched-workload H.264/HEVC performance.
- Actual Mac pipeline measurements and input-to-visible-response latency.

**No end-to-end latency number has been measured.** Zero added video buffering, FPS, host-only timing, and the audio output smoke test are not input-to-photon latency measurements. No phone-dependent test was performed after disconnection. Nothing was uploaded or published.
