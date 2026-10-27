"""Verify retained source archives and prepare the local build cache."""
from pathlib import Path
import hashlib, tarfile
root = Path(__file__).resolve().parents[1]
cache = Path('/private/tmp/cabledex-backend-build-20261027')
cache.mkdir(exist_ok=True)
archives = [
 ('cabledex-ffmpeg-9.0.2.tar.xz', '8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e', 'ffmpeg-9.0.2'),
 ('cabledex-sdl-3.4.18.tar.gz', 'c4b08b950bd29d83caae0ab8d884298d27046a9d30700fb42841c50992665c90', 'SDL-release-3.4.18'),
]
for name, digest, directory in archives:
 archive = root / 'Backend/archives' / name
 if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
  raise SystemExit('Source integrity failed: ' + name)
 if not (cache / directory).exists():
  with tarfile.open(archive) as source: source.extractall(cache, filter='data')
print('Pinned SDL and FFmpeg sources verified.')

# Published source snapshots preserve dependency source without nested Git metadata.
archive = root / 'Backend/archives/cabledex-scrcpy-5.0.1-source.tar.gz'
if hashlib.sha256(archive.read_bytes()).hexdigest() != 'bd4edc5c6d0c3fbb62feab7ecd525afd774c2d408c57ba8630c86a978b40da9e':
 raise SystemExit('Source integrity failed: cabledex-scrcpy-5.0.1-source.tar.gz')
if not (root / 'Backend/scrcpy').exists():
 with tarfile.open(archive) as source: source.extractall(root / 'Backend', filter='data')
archive = root / 'Backend/archives/cabledex-pkgconf-2.5.1-source.tar.gz'
if hashlib.sha256(archive.read_bytes()).hexdigest() != '8e152a52870ef0a3690c076115225e58d1ce472e56d1dbbc9a51e71277c39626':
 raise SystemExit('Source integrity failed: cabledex-pkgconf-2.5.1-source.tar.gz')
if not (root / 'Backend/pkgconf').exists():
 with tarfile.open(archive) as source: source.extractall(root / 'Backend', filter='data')
print('Pinned scrcpy and pkgconf snapshots verified and prepared.')
