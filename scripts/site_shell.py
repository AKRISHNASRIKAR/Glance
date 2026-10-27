"""Read the shared website shell from the landing page for static companion pages."""
from pathlib import Path
import re
root=Path(__file__).resolve().parent.parent

def shell():
    templates=root/'scripts/templates'
    return tuple((templates/name).read_text().strip() for name in ['site-header.html','site-footer.html','site-fonts.html'])
