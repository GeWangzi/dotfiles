# fonts

Self-hosted copies of the two faces the Retro RPG desktop design specifies.
Both are Google Fonts and both are under the SIL Open Font License 1.1; the
licence text for each is next to the font file.

| file | family | used for |
|---|---|---|
| `Silkscreen-Regular.ttf` | Silkscreen | labels, numbers, app names, key hints |
| `Silkscreen-Bold.ttf` | Silkscreen Bold | the same, where the design asks for 700 |
| `DotGothic16-Regular.ttf` | DotGothic16 | body copy in detail strips, toast messages, tip lines |

Fetched from the upstream Google Fonts repository:

```
https://raw.githubusercontent.com/google/fonts/main/ofl/silkscreen/Silkscreen-Regular.ttf
https://raw.githubusercontent.com/google/fonts/main/ofl/silkscreen/Silkscreen-Bold.ttf
https://raw.githubusercontent.com/google/fonts/main/ofl/dotgothic16/DotGothic16-Regular.ttf
```

They are committed here rather than installed from a package because the
design handoff requires them to be self-hosted for an offline desktop, and
because the AUR alternative is `ttf-google-fonts-git`, which is the entire
Google Fonts catalogue for the sake of three files. Total cost here is 2.1 MB,
almost all of it DotGothic16, which carries a large kana and kanji range.

`stow -t ~ fonts` links the directory into `~/.local/share/fonts`, and
`fc-cache -f` is required afterwards before anything can see them.

## Sizing

Silkscreen is a pixel face and this machine runs its panel at scale 1.5, so a
size only lands on whole physical pixels when the logical size is even
(`12px` renders at 18, `11px` renders at 16.5 and fringes). Round every
Silkscreen size in the design to the nearest even number before using it. The
design's 9px floor becomes 10px.

DotGothic16 is an outline face and is unaffected.
