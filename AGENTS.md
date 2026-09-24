# Agent guide

Project layout, data flow and checks are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Verifying UI changes

Check behavior as text over IPC rather than by screenshots. Reload the shell after
QML changes, then drive and read the running app:

```sh
C=io.github.dmitry-solomadin.omastocks
omarchy restart shell && omarchy-shell $C open
omarchy-shell $C view market                        # stock, market or watchlist
omarchy-shell $C dump crossAssets                   # visible text under an objectName; no name dumps the window
omarchy-shell $C activate crossAssetsView_global    # click a named button or switch
journalctl --user --since "-2 min" | grep -iE "omastocks.*(warn|error)"
```

`dump` prints one line per visual row. `*` marks bold (selected) text and `[name]`
marks items that `activate` can reach. Always grep the journal: QML runtime errors,
such as JavaScript Qt's engine lacks (`flatMap`), only show up there, and they can
leave the page blank while every test passes.

Give new interactive elements an `objectName`. Buttons activate through `clicked()`;
anything else (a `TapHandler`, a clickable label) needs an `activate()` function.

Take a screenshot only when the question is visual: layout, spacing, color, theming,
clipping or elision. Capture the window once with `grim` at its `hyprctl clients`
geometry, and make the text checks first.
