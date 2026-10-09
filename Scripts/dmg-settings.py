"""Quiet, dependency-backed Finder layout for the direct-download DMG."""
application = defines["app"]  # Provided by Scripts/release.py.
format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {"ScreenplayOS.app": (155, 170), "Applications": (425, 170)}
window_rect = ((120, 120), (580, 350))
background = "#f5f6f5"
default_view = "icon-view"
icon_size = 112
text_size = 14
show_toolbar = False
show_status_bar = False
show_sidebar = False
