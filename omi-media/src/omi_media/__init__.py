"""omi_media — Omi media launcher (Omi Media Launcher spec).

A small, keyboard-first, local playlist launcher for Ominty.  The DMS
popup is one presentation layer over this tool; the CLI is the contract.

Playlists live in four configured directories (Audio, Courses, Music,
Video under a root — `/home/martin/Playlist` by default) and are
discovered by scanning for `.m3u` / `.m3u8` / `.pls`.  Selecting a
playlist hands the file to that category's configured player.
"""

__version__ = "0.1.0"