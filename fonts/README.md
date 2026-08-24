# fonts

Self-hosted copy of the label face the Retro RPG desktop design specifies. It
is a Google Font under the SIL Open Font License 1.1; the licence text sits
next to the font file.

| file | family | used for |
|---|---|---|
| `Silkscreen-Regular.ttf` | Silkscreen | labels, numbers, app names, key hints |
| `Silkscreen-Bold.ttf` | Silkscreen Bold | the same, where the design asks for 700 |
| `LilitaOne-Regular.ttf` | Lilita One | DREAM LAND's labels -- the heavy Star Allies HUD lettering (the game's own face is Fontworks' Raglan Punch, which is commercial; Lilita One is the closest open face) |
| `Baloo2-VariableFont_wght.ttf` | Baloo 2 | DREAM LAND's body copy -- rounded and legible where Pixelify Sans' digits were not (its 2/5/9 collapse toward 8 at UI sizes) |

Body copy is **DejaVu Sans Mono**, the terminal's own face, from `ttf-dejavu`.
The design's body face was DotGothic16 and it was dropped 2026-08-21 at the
user's request: it is not a face they like, and taking the terminal's face
instead means the shell surfaces and the terminal read in one voice. To bring
it back, refetch the file below and swap the family name in the QML.

Fetched from the upstream Google Fonts repository:

```
https://raw.githubusercontent.com/google/fonts/main/ofl/silkscreen/Silkscreen-Regular.ttf
https://raw.githubusercontent.com/google/fonts/main/ofl/silkscreen/Silkscreen-Bold.ttf
https://raw.githubusercontent.com/google/fonts/main/ofl/dotgothic16/DotGothic16-Regular.ttf
```

The Silkscreen files are committed here rather than installed from a package
because the design handoff requires them to be self-hosted for an offline
desktop, and because the AUR alternative is `ttf-google-fonts-git`, which is
the entire Google Fonts catalogue for the sake of two files. They cost 27 KB
between them; the DotGothic16 file that used to sit beside them was 2 MB of
kana and kanji on its own, and went with the face.

`stow -t ~ fonts` links the directory into `~/.local/share/fonts`, and
`fc-cache -f` is required afterwards before anything can see them.

## Sizing

Silkscreen is a pixel face and this machine runs its panel at scale 1.5, so a
size only lands on whole physical pixels when the logical size is even
(`12px` renders at 18, `11px` renders at 16.5 and fringes). Round every
Silkscreen size in the design to the nearest even number before using it. The
design's 9px floor becomes 10px.

DejaVu Sans Mono is an outline face and is unaffected.
