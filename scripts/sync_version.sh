#!/bin/bash
# Syncs pubspec.yaml version with the current git branch name.
# Branch format: V0.0.4 or V0.0.4.1 → pubspec version: 0.0.4+1
# Usage: ./scripts/sync_version.sh

BRANCH=$(git branch --show-current 2>/dev/null)

if [[ -z "$BRANCH" ]]; then
  echo "Not on a branch (detached HEAD?), skipping version sync."
  exit 0
fi

# Extract version from branch name (strip leading V/v)
VERSION=$(echo "$BRANCH" | sed -n 's/^[vV]\([0-9].*\)/\1/p')

if [[ -z "$VERSION" ]]; then
  echo "Branch '$BRANCH' doesn't look like a version branch, skipping."
  exit 0
fi

# Convert 4-part version (0.0.4.1) to Flutter format (0.0.4+1)
# If 3-part (0.0.4), use +1 as default build number
if [[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)$ ]]; then
  FLUTTER_VERSION="${BASH_REMATCH[1]}+${BASH_REMATCH[2]}"
elif [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  FLUTTER_VERSION="${VERSION}+0"
else
  echo "Unrecognized version format: $VERSION"
  exit 1
fi

PUBSPEC="pubspec.yaml"
if [[ ! -f "$PUBSPEC" ]]; then
  PUBSPEC="$(git rev-parse --show-toplevel)/pubspec.yaml"
fi

CURRENT=$(grep -oP '^version: \K.*' "$PUBSPEC")

if [[ "$CURRENT" == "$FLUTTER_VERSION" ]]; then
  echo "Version already in sync: $FLUTTER_VERSION"
  exit 0
fi

sed -i "s/^version: .*/version: $FLUTTER_VERSION/" "$PUBSPEC"
echo "✅ Updated pubspec.yaml version: $CURRENT → $FLUTTER_VERSION (from branch $BRANCH)"
