#!/usr/bin/env python3
"""Bundle the canonical website system and page layouts; emit token compatibility copy."""
from pathlib import Path
import re
root=Path(__file__).resolve().parent.parent/'frontend'
system=(root/'design-system.css').read_text()
(root/'site.css').write_text(system+'\n'+(root/'site-pages.css').read_text())
tokens=re.search(r':root\{.*?\}',system,re.S)[0]
(root/'design-tokens.css').write_text('/* Generated from design-system.css. */\n'+tokens+'\n')

# The landing page retains the earlier design at the user's request.
landing=root/'landing'
names=['styles.css','hero.css','native-preview.css','motion.css','pomodoro-preview.css','macbook-m4.css','performance.css','design-tokens.css','design-system.css','site-pages.css']
(root/'landing.css').write_text('\n'.join((landing/name).read_text() for name in names))
