# STATE — Folder Watch for VLC

## Position

- **1.0.0** released for macOS, VLC 3.0.x. Passes the headless suite (43 checks).
- Distribution: GitHub releases and issues.

## Known limits

- A rebuild collapses the sidebar's expanded folders. Not fixable from an add-on:
  VLC 3's Lua API cannot add rows to a sidebar tree, and `vlc.playlist.delete`
  returns success but ignores sidebar rows (verified on 3.0.23).
- Rebuilds are deferred while anything from a watched folder is playing or
  paused, because VLC stops playback when the playing row disappears.

## Next

- 1.1: Windows and Linux. The scripts already derive VLC's data folder per
  platform and carry PowerShell / zenity folder choosers, all untested.
  `install.sh` needs a Windows counterpart.

## Facts about VLC 3.0.23's Lua API that shaped the design

- Folders enqueued in the Playlist never expand until played; preparsing does
  not expand them.
- Services-discovery scripts have no `vlc.net`, `vlc.io` or `vlc.misc`; a
  folder is listed with `vlc.stream(uri):readdir()`.
- Interface scripts have no `should_die()`; VLC cancels the thread inside
  `mwait()` on quit.
- `io.popen` and `os.execute` are available, which is how the native folder
  dialog is opened.
- With `extraintf=luaintf` already set in `vlcrc`, a test run must pass
  `--extraintf ""` or two watchers run at once and every log line doubles.
