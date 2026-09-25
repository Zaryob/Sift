#!/bin/sh
# Re-export the approved artwork using macOS's native image tools.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
artwork_dir="$project_dir/docs/icons"
catalog_dir="$project_dir/Sift/Assets.xcassets/AppIcon.appiconset"
iconset_dir="$artwork_dir/Sift.iconset"
mkdir -p "$catalog_dir" "$iconset_dir"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=""
    if [ "$scale" -eq 2 ]; then suffix="@2x"; fi
    filename="icon_${size}x${size}${suffix}.png"
    sips -z "$pixels" "$pixels" "$artwork_dir/Sift-macOS-master.png" --out "$iconset_dir/$filename" >/dev/null
    cp "$iconset_dir/$filename" "$catalog_dir/$filename"
  done
done
sips -z 1024 1024 "$artwork_dir/Sift-square-master.png" --out "$catalog_dir/AppIcon-iOS-1024.png" >/dev/null
iconutil -c icns "$iconset_dir" -o "$artwork_dir/Sift.icns"
echo "Exported AppIcon.appiconset, Sift.iconset and Sift.icns."

