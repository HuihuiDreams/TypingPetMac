"""Finder layout for the Typing Pet drag-and-drop installer (dmgbuild 1.6.7)."""
from pathlib import Path

application = str(Path(defines['app']).resolve())
format = 'UDZO'
filesystem = 'HFS+'
files = [application]
symlinks = {'Applications': '/Applications'}
hide_extension = ['TypingPet.app']
icon = str(Path(application) / 'Contents/Resources/AppIcon.icns')
background = defines['background']
# Leave room for Finder's globally enabled tab/path/status bars as well.
window_rect = ((200, 200), (760, 565))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
show_icon_preview = False
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = 'bottom'
text_size = 15
icon_size = 136
icon_locations = {'TypingPet.app': (175, 235), 'Applications': (585, 235)}
