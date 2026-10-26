"""Lightweight tracked-file hygiene; not a replacement for GitHub secret scanning."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
errors = []
for name in filter(None, files):
    p = root / name
    if name.startswith(('Assets/', 'Research/', 'build/', 'dist/')) or p.suffix in {'.f32', '.ogg', '.p12', '.p8', '.dylib', '.o'}:
        errors.append(f'Forbidden tracked artifact: {name}')
    if p.stat().st_size > 1_000_000:
        errors.append(f'Unexpected large file: {name}')
    text = p.read_text(encoding='utf-8')
    if re.search(r'/' + r'Users/[^/\s]+/', text):
        errors.append(f'Personal absolute path: {name}')
    if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}', text):
        errors.append(f'Possible credential: {name}')
for p in (root / '.github/workflows').glob('*.yml'):
    for action in re.findall(r'uses:\s+([^\s]+)', p.read_text()):
        if not re.fullmatch(r'[\w-]+/[\w-]+@[0-9a-f]{40}', action):
            errors.append(f'Action must be SHA-pinned: {action}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'Repository checks passed ({len(list(filter(None, files)))} tracked files).')
