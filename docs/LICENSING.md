# Licensing notes

## What this project is

Three Lua scripts, an installer, a test suite and documentation, all written
for this project by ACE Global Pro and released under the MIT licence
(see `LICENSE`). Copyright holder: ACE Global Pro, 2026.

## Relationship to VLC and VideoLAN

The scripts are add-ons that VLC 3 loads and runs through its documented Lua
interfaces: a services-discovery script (`lua/sd/`), an interface script
(`lua/intf/`) and an extension (`lua/extensions/`). They call the API that VLC
exposes to such scripts (`vlc.sd`, `vlc.stream`, `vlc.net`, `vlc.io`,
`vlc.playlist`, `vlc.dialog`, `vlc.config`, `vlc.misc`, `vlc.strings`,
`vlc.msg`). They contain no code copied or adapted from VLC, from VideoLAN's
bundled scripts, or from any other project. VLC's bundled Lua scripts ship
compiled on macOS and were not read or used as a source.

VLC is licensed under the GPL and LGPL. These scripts are not linked with VLC
and are not distributed with it; they are interpreted at run time. VideoLAN's
own documentation states that add-ons need not follow VideoLAN's licensing.
Should a stricter view ever treat scripts that use a GPL interpreter's
bindings as combined with it, the MIT licence is GPL-compatible, so no
obligation is breached either way.

## Third-party material

- **VLC's default "ignored extensions" list.** Both `lua/sd/folderwatch.lua`
  and `lua/intf/folderwatch.lua` carry the same default value that VLC uses
  for its `ignore-filetypes` option (a comma-separated list of file
  extensions such as `m3u,db,nfo,ini,jpg,...`), so that the tree hides the same
  files VLC itself would hide. This is a factual configuration value, not
  program code. Users can override it with the `ignore=` setting.
- **The MIT licence text** itself.
- Nothing else. There are no dependencies, libraries, vendored code, fonts or
  icons.

## Screenshot

`docs/screenshot-sidebar.jpg` was taken by the project author on the author's
own Mac and shows VLC's sidebar with the Folder Watch entry. It contains no
VideoLAN logo and no personal data beyond the author's own top-level folder
names.

## Trademarks

VLC, VideoLAN and the VLC cone logo are trademarks of the VideoLAN
non-profit organisation. This project uses the names VLC and VideoLAN only to
identify the player the add-on works with, does not use the logo, and is not
affiliated with or endorsed by VideoLAN.
