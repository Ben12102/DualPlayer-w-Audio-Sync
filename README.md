# Play two playlists side by side

[![Import](https://cdn.infobeamer.com/s/img/import.png)](https://info-beamer.com/use?url=https://github.com/info-beamer/package-dual-player)

This is a small example package showing how to build a simple player
that displays two independant playlists side by side. Should be easy
to change if you need other layouts.

Playback works by preloading the next asset while the current one
is playing. This means that at most 4 videos are loaded at the
same time.

You should *not* attempt to play two FullHD videos next to each other.
Doing so might be too much for the Pi and it might cause a lost
video signal as the Pi cannot generate and HDMI output signal
fast enough. It's best to use videos/images that exactly fit into the
available space.
