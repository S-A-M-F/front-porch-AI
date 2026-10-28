#!/usr/bin/env bash
#
# rotate-rawhide-notes.sh — clear the notes a nightly just shipped.
#
#   tools/rotate-rawhide-notes.sh <tag> [<shipped-sha>]
#
#   <tag>          the nightly's release tag, nightly-rawhide.YYYYMMDD.<sha>
#   <shipped-sha>  the commit that nightly was built from; defaults to the
#                  short sha at the end of the tag
#
# docs/Rawhide.md holds only the bullets that have not shipped in a nightly
# yet; the nightly workflow pastes them into the release body, which the
# in-app Update dialog shows. This script removes every bullet that was in
# the file at <shipped-sha> (those went out in that build) and records the
# tag on the "Last shipped nightly:" line. A bullet added to Rawhide after
# that commit stays, so a push that lands while the nightly is building is
# never lost. Running it twice for the same tag changes nothing.
#
# The nightly runs this after it publishes, then commits the file back to
# Rawhide (see the `rotate-notes` job in .github/workflows/nightly.yml).
# Run it by hand after a manual nightly, or with --dry-run to see the
# result on stdout without writing.
set -euo pipefail

FILE=docs/Rawhide.md
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
TAG=${1:?usage: $0 [--dry-run] <tag> [<shipped-sha>]}
SHA=${2:-${TAG##*.}}

cd "$(git rev-parse --show-toplevel)"

case "$TAG" in
  nightly-rawhide.*) ;;
  *) echo "tag should look like nightly-rawhide.YYYYMMDD.<sha>, got '$TAG'" >&2; exit 2 ;;
esac

# Bullets that were under the heading when the nightly was built.
shipped=$(git show "$SHA:$FILE" 2>/dev/null | awk '/^## /{on=1; next} on && /^- /') \
  || { echo "cannot read $FILE at $SHA" >&2; exit 1; }

# The file as it is now: everything through the heading, then the bullets.
head=$(awk '{print} /^## /{exit}' "$FILE")
body=$(awk '/^## /{on=1; next} on && NF' "$FILE")

kept=$(printf '%s\n' "$body" | grep -Fxv -f <(printf '%s\n' "$shipped") || true)

out=$(
  printf '%s\n' "$head" | sed -E "s|^Last shipped nightly: .*|Last shipped nightly: \`$TAG\`|"
  echo
  if [ -n "$kept" ]; then printf '%s\n' "$kept"; fi
)

if [ "$DRY" = 1 ]; then
  printf '%s\n' "$out"
  exit 0
fi

printf '%s\n' "$out" > "$FILE"
removed=$(( $(printf '%s\n' "$body" | grep -c '^- ' || true) - $(printf '%s\n' "$kept" | grep -c '^- ' || true) ))
echo "$FILE: removed $removed shipped bullet(s); last shipped nightly is now $TAG"
