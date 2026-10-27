#!/usr/bin/env python3
"""Check publishable files without printing credential values. Ignores local caches."""
from pathlib import Path
import re, subprocess, sys
root=Path(__file__).resolve().parent.parent
paths=subprocess.check_output(['git','ls-files','-co','--exclude-standard','-z'],cwd=root).decode().split('\0')
patterns={
    'private key':re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub credential':re.compile(rb'\b(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}'),
    'AWS access key':re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'Slack credential':re.compile(rb'\bxox[baprs]-[A-Za-z0-9-]{20,}'),
}
forbidden=re.compile(r'(^|/)(\.env(?:\..*)?|auth\.json|connection\.json|statistics\.json|focus-preferences\.json|node_modules|\.test-results|\.vercel|project-walkthrough)(/|$)|\.(pem|key|p12|provisionprofile)$')
findings=[];checked=0
for name in sorted(set(paths)):
    if not name:continue
    path=root/name
    if not path.is_file():continue
    if forbidden.search(name) and path.name!='.env.example':findings.append((name,'local/credential file is publishable'))
    if path.stat().st_size>3_000_000:continue
    data=path.read_bytes();checked+=1
    for label,pattern in patterns.items():
        if pattern.search(data):findings.append((name,label))
if '--history' in sys.argv:
    objects=subprocess.check_output(['git','rev-list','--objects','--all'],cwd=root).decode().splitlines()
    names={line.split(' ',1)[0]:line.split(' ',1)[1] if ' ' in line else '(object)' for line in objects}
    process=subprocess.Popen(['git','cat-file','--batch'],cwd=root,stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    historical=0
    for oid,name in names.items():
        process.stdin.write((oid+'\n').encode());process.stdin.flush()
        header=process.stdout.readline().decode().split()
        if len(header)!=3:continue
        size=int(header[2]);data=process.stdout.read(size);process.stdout.read(1)
        if header[1]!='blob' or size>3_000_000 or b'\0' in data:continue
        historical+=1
        for label,pattern in patterns.items():
            if pattern.search(data):findings.append((name,f'{label} in historical blob {oid[:12]}'))
    process.stdin.close();process.wait()
    print(f'History audit: {historical} text blobs checked.')
for name,label in findings:print(f'{name}: {label}')
print(f'Public-file audit: {checked} files checked; {len(findings)} findings.')
sys.exit(bool(findings))
