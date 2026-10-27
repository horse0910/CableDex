#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/build"
/usr/bin/swiftc -swift-version 5 -target arm64-apple-macos13.0 \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -framework CryptoKit \
  "$PROJECT_DIR/Sources/Core.swift" "$PROJECT_DIR/Sources/Bridge.swift" "$PROJECT_DIR/Sources/Transfers.swift" "$PROJECT_DIR/Tests/CoreTests.swift" \
  -o "$PROJECT_DIR/build/CoreTests"
"$PROJECT_DIR/build/CoreTests"
/usr/bin/swiftc -swift-version 5 -target arm64-apple-macos13.0 \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -framework CryptoKit \
  "$PROJECT_DIR/Sources/Core.swift" "$PROJECT_DIR/Sources/Bridge.swift" \
  "$PROJECT_DIR/Sources/Transfers.swift" "$PROJECT_DIR/Sources/SessionController.swift" "$PROJECT_DIR/Tests/SessionTests.swift" \
  -o "$PROJECT_DIR/build/SessionTests"
"$PROJECT_DIR/build/SessionTests"
/usr/bin/swiftc -swift-version 5 -target arm64-apple-macos13.0 \
  -module-cache-path "$PROJECT_DIR/build/module-cache" -framework CryptoKit \
  "$PROJECT_DIR/Sources/Core.swift" "$PROJECT_DIR/Sources/Bridge.swift" "$PROJECT_DIR/Sources/Transfers.swift" \
  "$PROJECT_DIR/Sources/SessionController.swift" "$PROJECT_DIR/Tests/TransferTests.swift" \
  -o "$PROJECT_DIR/build/TransferTests"
"$PROJECT_DIR/build/TransferTests"

POLICY_CONFIG=/private/tmp/cabledex-backend-build-20261027/client-v03-build/app
if [[ -f "$POLICY_CONFIG/config.h" && -f "$PROJECT_DIR/Backend/scrcpy/app/src/control_msg.h" ]]; then
  /usr/bin/clang -std=c11 -I"$PROJECT_DIR/Backend" -I"$PROJECT_DIR/Backend/scrcpy/app/src" \
    -I"$POLICY_CONFIG" -I/private/tmp/cabledex-backend-build-20261027/deps/include \
    "$PROJECT_DIR/Tests/BackendPolicyTests.c" -o "$PROJECT_DIR/build/BackendPolicyTests"
  "$PROJECT_DIR/build/BackendPolicyTests"
else
  echo 'Backend policy tests require the backend build cache; run scripts/build-backend.sh first.'
fi
