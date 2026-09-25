# Sift — vector app icon

The active app icon is [AppIcon.icon](../../Sift/AppIcon.icon), a native Icon Composer document with three editable SVG layers: Dot, Inner Wave and Outer Wave. The background and appearance overrides live in its `icon.json`.

- [Sift.svg](vector/Sift.svg): standalone full-color SVG with named groups.
- [Sift-dark.svg](vector/Sift-dark.svg): standalone dark SVG.
- [Sift-mono.svg](vector/Sift-mono.svg): transparent monochrome mark using `currentColor`.
- [layers](vector/layers): production SVG artwork with transparent 1024 × 1024 canvases.
- [previews](previews): Default, Dark, ClearLight, ClearDark, TintedLight and TintedDark exports from Apple's renderer.
- [Sift.iconset](Sift.iconset) and [Sift.icns](Sift.icns): static default-appearance exports for tools that need them.
- [legacy](legacy): archived raster iteration; no longer consumed by the app.

## Appearances

Default uses the cream background and orange gradients. Dark uses Apple's system-dark background and the same orange geometry. Mono uses a white silhouette; Icon Composer derives clear and tinted appearances from it. Tint color, lighting and the actual wallpaper are controlled by the OS; the blue preview tint is illustrative.

The Xcode target selects `AppIcon` in Debug and Release. Xcode compiles `Sift/AppIcon.icon` into the app's icon resources. SVG by itself is the editable source; the `.icon` package provides the system appearance behavior.

Open `Sift/AppIcon.icon` in Icon Composer to edit native materials and appearance overrides. To change geometry, edit the SVGs in `vector/layers`, then run:

```sh
sh scripts/export-app-icon.sh
```

This synchronizes the vector layers into the app package and regenerates the six previews, iconset and ICNS. The standalone full-color SVGs are reference compositions of the same geometry; update those when changing the layer shapes.

The vector artwork was redrawn as paths from the provided reference; it contains no embedded bitmap.

Reference: [Apple — Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
