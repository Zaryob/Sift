# Sift app icon

Artwork based on the user-supplied orange RSS reference. Generated with the built-in imagegen tool, then exported with macOS `sips` and `iconutil`.

- `Sift-square-master.png`: opaque, full-bleed artwork for iPhone/iPad.
- `Sift-macOS-master.png`: rounded tile with transparent surroundings for macOS.
- `Sift.iconset/`: the ten standard macOS entries (16, 32, 128, 256, 512 points at 1× and 2×).
- `Sift.icns`: standalone macOS icon.
- `../../Sift/Assets.xcassets/AppIcon.appiconset/`: production asset catalog containing macOS entries and the 1024 px iOS entry.

The Sift target selects `AppIcon` in both Debug and Release. Regenerate exports with `sh scripts/export-app-icon.sh`.

This set supplies the default appearance. The reference sheet's dark, clear, tinted and layered Icon Composer examples are not separate assets in this set.

## Generation prompts

### Square master

Use case: logo-brand.
Asset type: production app icon master for Sift RSS reader, a single 1024 x 1024 square PNG.
Input image: visual reference only. Recreate ONLY the orange RSS symbol from the leftmost Default icon, on its warm ivory background.
Primary request: produce one clean high-resolution standalone icon source, NOT the reference presentation sheet.
Subject: a generous orange-to-red RSS mark consisting of a circular lower-left dot and two thick curved quarter-circle waves, with soft rounded ends. Preserve the elegant tapered ribbon silhouette and subtle red folded edge on the right outer wave from the reference. Yellow-orange highlights at upper left, vivid orange center and red-orange lower-right ends. Balanced placement, emblem occupies central 74 percent width and height.
Background: warm ivory cream, subtle smooth tonal shading; fully opaque background extends completely to all four straight edges of the square canvas. No rounded-square outer silhouette and no margins outside the background: operating systems will mask the icon.
Style: precise polished smooth brand artwork, crisp contours, gentle restrained depth in ribbons, no blur, no grain.
Constraints: exactly one RSS dot and exactly two waves. Front facing, no perspective. No words, letters, labels, watermark, device mockup, layout, borders, surrounding scenery, or extra icons. Square full bleed opaque cream canvas.

### macOS master

Use case: precise-object-edit.
Asset type: final macOS app icon PNG with real alpha transparency, square canvas.
Input: the supplied full-bleed cream and orange Sift icon is the edit target.
Change ONLY the outer silhouette and canvas layout for macOS delivery. Preserve the exact orange RSS emblem, cream fill, relative emblem scale and design of the input.
Fit the entire input artwork inside a large centered cream rounded square (Apple-style continuous rounded corners), with about 8% transparent canvas margin on all sides. The tile occupies 84% of the canvas width and height. Corner radius is about 22% of tile width. Very subtle white bevel at top edge and a soft restrained contact shadow below the tile. True transparent pixels outside the rounded square and shadow; no white backdrop, no checkerboard drawn into image.
One icon only, front facing, no perspective, no text, no label, no extra visual elements. Output square 1024x1024 or higher resolution.

### macOS edge refinement

Edit target: supplied macOS RSS icon. Keep the emblem, the cream tile, their geometry, positions and all colors unchanged. Refine only the external alpha edge: remove ALL detached white speckles, fuzzy white fringe, noise and stray pixels above and around the tile. Make the rounded-square silhouette perfectly smooth with clean anti-aliased edges and fully transparent exterior. Remove the heavy bottom shadow; retain only a tiny soft subtle shadow touching the tile. This is a production app icon, with absolutely pristine edges at 16px and 1024px. No white outer halo. Preserve the current canvas size and transparent padding.
