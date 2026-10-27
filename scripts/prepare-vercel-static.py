#!/usr/bin/env python3
"""Prepare only static frontend assets for the linked Vercel project."""
from pathlib import Path
import json, shutil, subprocess
root=Path(__file__).resolve().parent.parent
subprocess.run(['python3',str(root/'scripts/sync-extension-dashboard.py')],check=True)
output=root/'.vercel/output'
output.mkdir(parents=True,exist_ok=True)
static=output/'static'
if static.exists():shutil.rmtree(static)
shutil.copytree(root/'frontend',static,ignore=shutil.ignore_patterns('.*','*.md','node_modules','*.map','*.pem','*.key','*.p12','*.provisionprofile','auth.json','connection.json','statistics.json','focus-preferences.json'))
routes=[{'src':'^/$','dest':'/index.html'}]
for path in ['/extension','/extension/connect','/extension/dashboard']:
    routes.extend([{'src':'^'+path+'$','status':308,'headers':{'Location':path+'/'}},{'src':'^'+path+'/$','dest':path+'/index.html'}])
routes.append({'handle':'filesystem'})
(output/'config.json').write_text(json.dumps({'version':3,'routes':routes},indent=2)+'\n')
print(output)
