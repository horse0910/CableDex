# CableDeX 0.3 access summary

| Allowed when requested/enabled | Blocked in the app/client |
|---|---|
| Detect/select a physical USB phone | Wireless/TCP device connections and discovery |
| Copy/run the verified temporary mirroring server | APK installation and viewer file drops |
| Screen video and Android output audio | Microphone capture and recording |
| Text clipboard in both directions | Clipboard reads/writes when switched off or view-only |
| Selected files through the native send/receive UI | Automatic file sync, recursive copy, phone-file deletion UI |
| Keyboard/mouse, optional panel-off/keep-active | Lock-screen bypass and persistent lock/timeout changes |
| Temporary secondary-display freeform request/cleanup | Primary-display windowing mutation and generic device-shell UI |

The custom client's positive control-message allowlist allows display input and gates clipboard messages on an explicit per-launch setting. Clipboard read/write handlers also check the gate. Audio defaults off unless the wrapper explicitly enables it and always uses Android output capture. Recording and network connection helpers remain disabled in compiled code. The raw viewer pusher accepts only the verified temporary server at its fixed path; native selected file transfer is a separate reviewed implementation.

Native transfers revalidate the authorized USB serial and transport ID. Phone paths are limited lexically to `/sdcard` or `/storage/emulated/0`; traversal and control characters are rejected. These are app checks, not an OS sandbox. Shell arguments for listing/mkdir/move/test are quoted. Uploads accept regular local files and use a fresh folder. Receives stage privately, reject symlink destinations, and require a save-panel choice for replacement. Received files are not opened or executed automatically. Shared-storage directory listings and selected file bytes are accessed when using the browser/transfer controls.

**ADB permission itself remains broad.** Android authorizes a Mac debugging key, not individual CableDeX features. Other programs under your Mac account may use that authorization. Turn off debugging or revoke authorization when no longer needed. Temporary server copy/execution, display creation, input, clipboard, selected files, and audio mean that more than pixels cross USB, as requested for this build.

Pinned hashes and ad-hoc signatures detect selected artifact changes; they are not notarization or a malware certification. This review covers modified app paths and selected upstream integrations, not an exhaustive audit of every dependency or operating-system component. The phone remains disconnected; live behavior and latency are deferred. See VALIDATION.md.
