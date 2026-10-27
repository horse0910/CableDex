#!/bin/bash
# Offline output check: decodes PCM and feeds 250 ms of silence to the default Mac output.
# No phone and no microphone are accessed. Requires the local backend build cache.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$PROJECT_DIR" <<'PY'
import os, subprocess, shlex, sys
from pathlib import Path
root=Path(sys.argv[1])
prefix=Path('/private/tmp/cabledex-backend-build-20261027/deps')
env=dict(os.environ, PKG_CONFIG_LIBDIR=str(prefix/'lib/pkgconfig'))
flags=shlex.split(subprocess.check_output([str(prefix/'bin/pkgconf'),'--static','--libs','sdl3','libavcodec','libavutil'],env=env,text=True))
subprocess.run(['/usr/bin/clang','-mmacosx-version-min=13.0','-I'+str(prefix/'include'),'-L'+str(prefix/'lib'),str(root/'Tests/AudioSmoke.c'),*flags,'-o',str(root/'build/AudioSmoke')],check=True)
subprocess.run([str(root/'build/AudioSmoke')],check=True)
PY
