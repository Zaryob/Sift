#!/bin/sh
# Export all appearances from the editable Icon Composer / SVG source.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
artwork_dir="$project_dir/docs/icons"
icon_dir="$project_dir/Sift/AppIcon.icon"
iconset_dir="$artwork_dir/Sift.iconset"
developer_dir=$(xcode-select -p)
ictool="$developer_dir/../Applications/Icon Composer.app/Contents/Executables/ictool"
mkdir -p "$iconset_dir" "$artwork_dir/previews"
# SVG geometry is maintained under docs/icons/vector; sync it into the package.
cp "$artwork_dir"/vector/layers/*.svg "$icon_dir/Assets/"
for rendition in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  "$ictool" "$icon_dir" --export-image --output-file "$artwork_dir/previews/$rendition.png" --platform macOS --rendition "$rendition" --width 512 --height 512 --scale 1 --tint-color 0.60 --tint-strength 0.65 >/dev/null
done
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    suffix=""
    if [ "$scale" -eq 2 ]; then suffix="@2x"; fi
    "$ictool" "$icon_dir" --export-image --output-file "$iconset_dir/icon_${size}x${size}${suffix}.png" --platform macOS --rendition Default --width "$size" --height "$size" --scale "$scale" >/dev/null
  done
done
iconutil -c icns "$iconset_dir" -o "$artwork_dir/Sift.icns"
echo "Exported six appearances, Sift.iconset and Sift.icns from SVG layers."
