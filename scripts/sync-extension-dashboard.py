#!/usr/bin/env python3
"""Generate the hosted view from the extension UI and landing-page shell."""
from pathlib import Path
import re
root=Path(__file__).resolve().parent.parent
source=root/'browser-extension'
target=root/'frontend/extension/dashboard'
target.mkdir(parents=True,exist_ok=True)
for filename in ['core.js','ui.js']:
    (target/filename).write_text((source/'src'/filename).read_text())
(target/'ui.css').write_text((source/'ui.css').read_text())
from site_shell import shell
header,footer,fonts=shell()
html=(source/'options.html').read_text().replace('src="src/ui.js"','src="ui.js"').replace('icons/outline-48.png','/assets/logo.webp')
html=re.sub(r'<section class="card wide" id="pomodoro-settings">.*?</section>','',html,flags=re.S)
html=html.replace('<title>Glance Focus | Options</title>','<title>Focus dashboard | Glance</title><meta name="description" content="Your local Glance timer, website rules, Mac connection and activity. Paired Mac settings stay on your Mac.">')
html=html.replace('<link rel="stylesheet" href="ui.css">',fonts+'<link rel="stylesheet" href="/site.css"><link rel="stylesheet" href="ui.css"><script src="/navigation.js" defer></script>')
html=re.sub(r'<main><header>.*?</header>','<main id="main" class="dashboard-main wrap"><header class="dashboard-heading"><div><p class="eyebrow">Local focus dashboard</p><h1>Focus dashboard</h1></div><span id="connection" class="status">Connecting to your local extension…</span></header>',html,flags=re.S)
html=html.replace('<body data-page="options">','<body data-page="options"><a class="skip-link" href="#main">Skip to content</a>'+header)
html=html.replace('</main></body>','</main>'+footer+'</body>')
html=html.replace('<div class="stack">','<section id="dashboard-gate" class="card"><h2>Your focus starts locally.</h2><p>Open Glance Focus in Chrome and choose <strong>Open web dashboard</strong> to connect. Your timer and settings come from the extension and paired Mac.</p><p class="muted">Activity stays on your devices. No account required.</p><a class="primary dashboard-setup" href="../">Set up Glance Focus ↗</a></section><div class="stack" hidden>')
html=re.sub(r'<a id="options"[^>]*>.*?</a>','',html,flags=re.S)
html=html.replace('<div class="actions"><button id="open-dashboard">Open web dashboard</button><button id="revoke-dashboard">Disconnect web dashboard</button></div>','')
html=html.replace('<button id="connect" class="primary">','<button id="connect" class="primary" hidden>').replace('<button id="standalone" hidden>','<button id="standalone" hidden data-local-only>').replace('<button id="emergency" class="danger" hidden>','<button id="emergency" class="danger" hidden data-local-only>')
(target/'index.html').write_text(html)
print(target)

from site_metadata import generate
generate()
