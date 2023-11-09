# mpv-selectformat

* [Installation](#installation)
* [Features](#features)
* [Default Keys](#default-keys)

selectformat is an mpv script that allows you to select the
youtube-dl format of the video on the fly.

Based on the unmaintained
[mpv-youtube-quality](https://github.com/jgreco/mpv-youtube-quality).

![Folded](sc1.jpg)

![Unfolded](sc2.jpg)

## Installation

1. Download and copy `selectformat.lua` to your mpv's
[scripts folder](https://mpv.io/manual/stable/#script-location)

2. Add a binding to your mpv's
[input.conf file](https://mpv.io/manual/stable/#input-conf)
for opening the menu
(selectformat doesn't add such binding itself).
You could add something like this: `ctrl+f script-binding selectformat/menu`

## Features

- Formats are grouped (folded) based on resolution to reduce clutter
- Formats are properly sorted based on codec, protocol, etc.
- Formats are fetched asynchronously as soon as an internet video starts
- The initially-loaded format is pre-selected in the menu
- More useful info about the formats are displayed compared to mpv-youtube-quality

## Default Keys

| Key(s)                 | Function |
|------------------------|----------|
| `Up` or `k`            | Move up
| `Down` or `j`          | Move down
| `PageUp` or `Ctrl+u`   | Move up 5 items
| `PageDown` or `Ctrl+d` | Move down 5 items
| `Home` or `g`          | Jump to the first item
| `End` or `G`           | Jump to the last item
| `Right` or `l`         | Unfold the resolution under the cursor
| `Left` or `h`          | Fold the unfolded resolutions
| `Enter`                | Select the item under the cursor
| `Esc` or `q`           | Close the menu
