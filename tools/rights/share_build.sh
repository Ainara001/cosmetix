#!/usr/bin/env bash
# A build meant to be GIVEN to other people (investors, testers, a store):
# product photos whose rights are not confirmed are left out of the bundle.
#
#   tools/rights/share_build.sh ios --simulator --debug     # any `flutter build` arguments
#
# The photos stay in the working project: they are moved to a temporary folder
# for the time of the build and put back afterwards (also when the build fails
# or is interrupted). A product without its photo shows the neutral placeholder.
# Which photos are left out is decided by tools/rights/photo_rights.json
# (see tools/rights/photo_audit.py): everything that is not "cleared".
set -euo pipefail
cd "$(dirname "$0")/../.."

manifest=tools/rights/photo_rights.json
[ -f "$manifest" ] || { echo "no $manifest: run python3 -I tools/rights/photo_audit.py"; exit 1; }

# the manifest must describe exactly the files that are there
python3 -I - "$manifest" <<'PY'
import json, os, sys
m = json.load(open(sys.argv[1]))
listed = {os.path.basename(r['file']) for r in m['products']}
real = {f for f in os.listdir('assets/products') if f.endswith('.jpg')}
if listed != real:
    sys.exit('photo_rights.json is out of date: rerun tools/rights/photo_audit.py (%s)' % sorted(listed ^ real))
PY

hold="$(mktemp -d "${TMPDIR:-/tmp}/cosmetix_photos.XXXXXX")"
moved=()
restore() {
  for f in "${moved[@]:-}"; do
    [ -n "$f" ] && [ -f "$hold/$f" ] && mv "$hold/$f" "assets/products/$f"
  done
  rmdir "$hold" 2>/dev/null || true
}
trap restore EXIT INT TERM

while IFS= read -r f; do
  [ -f "assets/products/$f" ] || continue
  mv "assets/products/$f" "$hold/$f"
  moved+=("$f")
done < <(python3 -I - "$manifest" <<'PY'
import json, os, sys
for r in json.load(open(sys.argv[1]))['products']:
    if r['rights_status'] != 'cleared':
        print(os.path.basename(r['file']))
PY
)
echo "left out of this build: ${#moved[@]} product photos (rights not confirmed)"
flutter build "$@" --dart-define=COSMETIX_SHARE_BUILD=true
