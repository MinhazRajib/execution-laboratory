#!/usr/bin/env bash
# Export the ExecLab client as a static site in site/, ready for any static
# host (Vercel, GitHub Pages, S3). Needs the OxCaml + Bonsai preview toolchain
# the UI builds with, so run it on the machine you develop the UI on.
#
#   app/ui/export.sh            # builds in release mode, writes site/
#
# Release mode drops source maps and pretty-printing, which is what turns the
# ~70MB dev bundle into something a browser can download in a few seconds.
set -euo pipefail
cd "$(dirname "$0")/../.."

dune build --profile release app/ui/main.bc.js

rm -rf site && mkdir -p site
cp _build/default/app/ui/main.bc.js site/main.bc.js
# The dev page points at _build/; the exported page sits next to its bundle.
sed 's#\.\./\.\./_build/default/app/ui/main\.bc\.js#main.bc.js#' app/ui/index.html > site/index.html
cp vercel.json site/vercel.json

echo "site/ written:"
du -sh site/main.bc.js site/index.html
gzip -9 -c site/main.bc.js | wc -c | awk '{printf "  (%.1f MB gzipped over the wire)\n", $1/1048576}'
