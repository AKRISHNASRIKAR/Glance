#!/usr/bin/env python3
"""Regenerate the single landing-page stylesheet after editing CSS sources."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent / 'frontend'
names = ['styles.css', 'hero.css', 'native-preview.css', 'motion.css', 'pomodoro-preview.css', 'macbook-m4.css', 'performance.css']
(root / 'site.css').write_text('\n'.join((root / name).read_text() for name in names))
