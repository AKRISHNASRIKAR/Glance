"""Finder layout, generated directly without driving the Finder UI."""
from pathlib import Path
root = Path(defines['root']).resolve()
app = root / 'dist/Glance.app'
files = [str(app)]
symlinks = {'Applications': '/Applications'}
format = 'UDZO'
filesystem = 'HFS+'
background = str(root / 'dist/dmg-background.tiff')
icon = str(root / 'Resources/AppIcon.icns')
window_rect = ((240, 160), (660, 440))
icon_locations = {'Glance.app': (170, 230), 'Applications': (490, 230)}
icon_size = 96
text_size = 14
label_pos = 'bottom'
default_view = 'icon-view'
show_icon_preview = False
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
grid_spacing = 80
arrange_by = None
include_icon_view_settings = True
