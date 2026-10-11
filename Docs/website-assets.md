# Website asset provenance

The site screenshots show the signed ScreenplayOS 0.1.4 (27) app with the disposable, original “The Last Light” demo screenplay. No owner screenplay appears. `Website/assets/screenshots/outline-script.*` was captured earlier from the same build. `boards.*` and `edit.*` were recaptured after replacing all demo board images with the drawings below. Each PNG is a 2400 × 1520 window capture at 2×; its WebP is an optimized derivative. Captures were made from the app window, without the desktop or user files.

The twelve `Website/assets/demo-boards/NN.png` images are original local raster drawings made for this demonstration by `Website/tools/draw-demo-boards.py`. The drawing script uses Pillow shapes and lines; it does not fetch stock art, use a third-party image, or call any AI service. The demo project references copies of these files in a disposable `/private/tmp/screenplayos-demo-home` directory; no temporary project or user document is published. All frames are 1280 × 720.

| File | Scene and shot | Duration |
| --- | --- | ---: |
| `01.png` | Ferry cabin, establishing | 3.5 s |
| `02.png` | Ferry pulls away | 4 s |
| `03.png` | Lena in the cabin | 2.5 s |
| `04.png` | Lena and Ari begin | 5 s |
| `05.png` | Ferry terminal, establishing | 3.5 s |
| `06.png` | Lena and paper star | 4 s |
| `07.png` | Lena at the terminal | 2.5 s |
| `08.png` | Ferry arrives | 5 s |
| `09.png` | Harbor walk, establishing | 3.5 s |
| `10.png` | Ari raises the brass key | 4 s |
| `11.png` | Ari and the key | 2.5 s |
| `12.png` | Harbor signal lights | 5 s |

The authored board durations total **45 seconds** across three scenes. The drawn PNGs are source material for the screenshots and are intentionally omitted from the public site build; only the optimized screenshot images ship with the site.

The current 1.4 MB `Website/assets/ScreenplayOSLogo.png` is retained as the approved source. `Website/tools/export-brand.py` makes the 32 px favicon, 180 px Apple touch icon, and 88 px header PNG in `Website/assets/brand/`; each is under 30 KB. The public build copies only those derivatives. To use a new approved SVG later, run `python3 Website/tools/export-brand.py --source /path/to/new-mark.svg` (requires CairoSVG for SVG input). The HTML and public build paths need no changes.
