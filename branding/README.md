# Bucks brand assets

Everything here comes from one vector trace of the logo, so every size stays sharp.

| File | Use |
|---|---|
| `bucks_wordmark_white.svg`, `bucks_wordmark_purple.svg` | Master wordmark (transparent background) for print, web, decks |
| `bucks_logo_square.svg`, `bucks_logo_2160.png` | The square purple logo |
| `play_store_icon_512.png` | Play Console > Store listing > App icon |
| `play_feature_graphic_1024x500.png` | Play Console > Store listing > Feature graphic |

Brand purple: `#811FF0`. The app uses it for the theme's primary colour, the launcher icon and the splash screen.

## Regenerating

```sh
pip install pillow numpy potracer cairosvg
python3 branding/trace_logo.py path/to/logo.jpg     # writes letters.json (one vector path per letter)
python3 branding/generate_assets.py                  # writes the files above and the Android resources
```

`generate_assets.py` also writes, in the app:
- `res/drawable/ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml` and `res/mipmap-anydpi/ic_launcher.xml` (the adaptive launcher icon, including the Android 13 themed icon)
- `res/drawable/bucks_wordmark.xml` (the wordmark as a vector drawable)
- `res/drawable/ic_stat_bucks.xml` (notification icon: the "b")
- `ui/components/BrandPaths.kt` (the letter paths that the splash motion and the loader animate; see `ui/components/Brand.kt`)
