"""Finder layout, written directly to .DS_Store without GUI scripting."""

import os
import subprocess

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
default_view = "icon-view"
# Include room for the title bar and Finder's bottom bar on recent macOS versions.
window_rect = ((180, 140), (640, 500))
icon_locations = {"QuietLock.app": (170, 238), "Applications": (470, 238)}
icon_size = 104
text_size = 13
label_pos = "bottom"
arrange_by = None
# Setting FinderInfo to hide the extension would invalidate strict signature checks.
# Finder already displays application bundles without their extension by default.
hide_extensions = []

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_item_info = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False


def create_hook(mount_point, options):
    """Reject copies with damaged signatures before the image is compressed."""
    subprocess.run([
        "/usr/bin/codesign", "--verify", "--strict",
        os.path.join(mount_point, "QuietLock.app"),
    ], check=True)
