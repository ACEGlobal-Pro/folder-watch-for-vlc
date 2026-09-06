# Changelog

## 1.0.0 — 2026-09-06

First release. macOS, VLC 3.0.x.

- "Folder Watch" sidebar entry showing the chosen folders as a tree.
- Watcher rescans every 15 s (configurable) and rebuilds the tree on any change:
  deleted, added, renamed or replaced files and folders.
- Rebuild waits while anything from the watched folders is playing or paused.
- A folder whose drive is unmounted is left as it was, never emptied.
- Settings panel (View › Folder Watch for VLC) with the macOS folder chooser,
  interval, "Rescan now" and watcher status. First run opens the chooser.
- Installer with a one-time `--configure` step; uninstaller.
- Headless test suite that drives real VLC without a window.
