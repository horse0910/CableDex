"""Apply the reviewed patch to the pinned official scrcpy source; no network access."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
source = root / 'Backend/scrcpy'
if not (source / '.git').exists():
    import hashlib, json
    snapshot = json.loads((root / 'Backend/scrcpy-SNAPSHOT.json').read_text())
    if snapshot['upstreamCommit'] != 'a60891aea193d92e7e5c3942700eca63f9d19a5f':
        raise SystemExit('Unexpected vendored source commit')
    for name, digest in snapshot['files'].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Published source snapshot changed: ' + name)
    if (source / 'app/src/cabledex_policy.h').read_bytes() != (root / 'Backend/CableDeXPolicy.h').read_bytes():
        raise SystemExit('Policy header does not match reviewed source snapshot')
    print('Verified published patched source snapshot. No patch needs reapplying.')
    raise SystemExit(0)
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
if base != 'a60891aea193d92e7e5c3942700eca63f9d19a5f':
    raise SystemExit('Unexpected scrcpy base commit')
(source / 'app/src/cabledex_policy.h').write_text((root / 'Backend/CableDeXPolicy.h').read_text())
if (source / 'CABLEDEX_PATCHED').exists():
    print('CableDeX policy already applied.')
else:
    patch = root / 'Backend/cabledex.patch'
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=source, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=source, check=True)
    (source / 'CABLEDEX_PATCHED').write_text('CableDeX display-only client patch v1\n')
    print('Applied display-only patch.')
