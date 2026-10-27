#!/usr/bin/env python3
"""Package only runnable extension assets, never tests, profiles or credentials."""
from pathlib import Path
import json, zipfile
root=Path(__file__).resolve().parent.parent
source=root/'browser-extension'
version=json.loads((source/'manifest.json').read_text())['version']
out=root/'dist'/f'Glance-Focus-{version}.zip';out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 for name in ['manifest.json','popup.html','options.html','blocked.html','ui.css','blocked.css']:
  z.write(source/name,name)
 for directory in ['src','icons']:
  for p in sorted((source/directory).rglob('*')):
   if p.is_file():z.write(p,p.relative_to(source))
print(out)
