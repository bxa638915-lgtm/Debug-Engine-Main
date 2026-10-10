# External V-Slice assets

Debug Engine can mount a local `Funkin.assets` checkout as source assets without copying it into this project.

Set one of these before starting the game:

- Put the path to the `Funkin.assets` repository (or its `assets` directory) in `config/vslice-assets-path.txt`.
- Set the `FUNKIN_ASSETS_PATH` environment variable.
- Pass `-vslice-assets "C:/path/to/Funkin.assets"` on the command line.

Command-line configuration takes precedence over the environment, which takes precedence over the config file. The config file is read from the game working directory. If the configured path is missing or does not contain an asset root (`data`, `images`, `songs`, `music`, or `fonts`), the game logs a warning and continues without mounting it.

V-Slice song metadata and charts are read from `data/songs/<song-id>/<song-id>-metadata.json` and `data/songs/<song-id>/<song-id>-chart.json`. Optional variation files use `-<variation>` before `.json`. Freeplay reads album definitions from `data/ui/freeplay/albums/<album-id>.json` and album artwork from the asset key in that definition. The external checkout stays separate from the DBE source tree.

In Freeplay, `Q` and `E` cycle through playable characters present in the loaded V-Slice songs. The chosen character replaces only the player character on a V-Slice chart; chart notes and opponent selection remain unchanged. Song previews use `playData.previewStart` and `previewEnd` as fractions of the instrumental and loop between those points.
