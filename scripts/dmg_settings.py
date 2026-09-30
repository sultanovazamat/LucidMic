# dmgbuild layout for the LucidMic installer window (see scripts/build.sh).
# `defines` is injected by dmgbuild from -D options.
app = defines["app"]  # noqa: F821
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["volume_icon"]  # noqa: F821
background = defines["background"]  # noqa: F821
window_rect = ((200, 140), (660, 460))  # matches the 660x460 background
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {"LucidMic.app": (165, 175), "Applications": (495, 175)}
