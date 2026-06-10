#!/usr/bin/env bash
set -euo pipefail

# Builds a thumbnail gallery (index.html + thumbs/) for a directory of QA
# capture PNGs. Usage: make-gallery.sh [captures-dir]

dir="${1:-.meta/multipass/runtime/loops/project/observe/qa-surface-coverage}"
cd "$dir"
mkdir -p thumbs

{
  echo '<!DOCTYPE html><html><head><meta charset="utf-8">'
  echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
  echo "<title>QA captures $(date '+%Y-%m-%d %H:%M')</title>"
  cat <<'CSS'
<style>
  body { background:#15151a; color:#ddd; font:14px -apple-system,sans-serif; margin:20px; }
  h1 { font-size:18px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)); gap:14px; }
  .card { background:#1e1e26; border:1px solid #333; border-radius:8px; padding:8px; }
  .card img { width:100%; border-radius:4px; display:block; }
  .card a { color:#9be; text-decoration:none; font-size:12px; }
  .name { margin-top:6px; }
</style>
CSS
  echo "</head><body><h1>QA surface captures &mdash; $(date '+%Y-%m-%d %H:%M')</h1><div class='grid'>"
  for png in *.png; do
    [ -e "$png" ] || continue
    thumb="thumbs/${png%.png}.jpg"
    if [ ! -f "$thumb" ] || [ "$png" -nt "$thumb" ]; then
      magick "$png" -resize 640x -quality 82 "$thumb"
    fi
    echo "<div class='card'><a href='$png' target='_blank'><img src='$thumb' loading='lazy'></a><div class='name'><a href='$png' target='_blank'>$png</a></div></div>"
  done
  echo '</div></body></html>'
} > index.html

echo "Gallery: $dir/index.html"
