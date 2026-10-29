# Film simulation camera icons

Source: [FUJIFILM X-T5 official manual, FILM SIMULATION](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/#film_simulation), retrieved 2026-10-29.

The official page uses icon fonts, rather than separate PNGs. Its [webfont.css](https://fujifilm-dsc.com/en/manual/x-t5/css/webfont.css) references `https://fujifilm-dsc.com/en/manual/fonts/fficn{30,32,33,62,63}.ttf`. These five original font files are stored in `Sources/FujiFrame/Resources/FilmSimulationFonts`. The artwork and fonts remain the property of their respective rights holders (FUJIFILM); this repository does not assign them a new license.

`FilmSimulationPicker.swift` maps all 20 existing X-T5 options, including the six monochrome filter variants, to the exact font and character used by the manual. CoreText reads glyph outlines directly without installing/registering fonts. Cached vector-backed template images appear before the name in the native menu and selected value; macOS supplies the appropriate light/dark and selected-menu colors. The stored recipe strings are unchanged. “未记录” has no icon.

SwiftPM copies the font folder into its resource bundle. `scripts/build-app.sh` includes that bundle inside the app. The generated Xcode project copies the same font folder directly to app resources. No runtime network access is needed.

Verification: `scripts/test.sh` includes a test that all supported simulations load distinct renderable template images from bundled resources. Build the distributable app with `scripts/build-app.sh`; regenerate the Xcode project with `python3 scripts/generate-project.py` after adding Swift sources.
