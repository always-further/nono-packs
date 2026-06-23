#!/usr/bin/env bash
# Release a nono pack: tags the commit, pushes the tag, optionally
# creates a GitHub release.
#
# The tag triggers the matching publish-<pack>.yml workflow which
# signs the artifacts with Sigstore and uploads them to the registry.
# The GitHub release itself is purely human-readable changelog
# metadata — `nono pull` does not consult GitHub for distribution.
#
# Usage:
#   scripts/release.sh <pack> <version> [--release] [--dry-run]
#
# Examples:
#   scripts/release.sh claude 0.0.4
#   scripts/release.sh codex 0.0.5 --release
#   scripts/release.sh claude 0.1.0 --release --dry-run

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: scripts/release.sh <pack> <version> [--release] [--dry-run]

  <pack>      Pack directory under repo root (e.g. claude, codex).
  <version>   Semver without the leading 'v' (e.g. 0.0.4).

Options:
  --release   Also create a GitHub release with auto-generated notes
              (requires `gh` authenticated). Off by default — the tag
              alone is enough to trigger publishing to the registry.
  --dry-run   Print the actions that would run; make no changes.
USAGE
  exit 2
}

[[ $# -ge 2 ]] || usage

PACK="$1"
VERSION="$2"
shift 2

CREATE_RELEASE=0
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CREATE_RELEASE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
  shift
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$REPO_ROOT" ]] || { echo "not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"

PACK_DIR="$REPO_ROOT/$PACK"
[[ -d "$PACK_DIR" ]] || { echo "pack directory not found: $PACK_DIR" >&2; exit 1; }
[[ -f "$PACK_DIR/package.json" ]] || { echo "missing $PACK/package.json" >&2; exit 1; }

WORKFLOW="$REPO_ROOT/.github/workflows/publish-$PACK.yml"
[[ -f "$WORKFLOW" ]] || {
  echo "no publish workflow at .github/workflows/publish-$PACK.yml" >&2
  echo "the tag will be created but nothing will publish to the registry" >&2
  exit 1
}

# Strip a leading 'v' if the user passed one accidentally; canonical
# input is bare semver.
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "version '$VERSION' is not valid semver (e.g. 0.0.4 or 1.2.3-rc.1)" >&2
  exit 1
fi

TAG="$PACK-v$VERSION"

# Refuse if the tag already exists locally or on origin.
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
  echo "tag $TAG already exists locally" >&2
  exit 1
fi
if git ls-remote --tags origin "refs/tags/$TAG" | grep -q "refs/tags/$TAG"; then
  echo "tag $TAG already exists on origin" >&2
  exit 1
fi

# Refuse on a dirty tree — published artifacts must reflect a commit
# anyone can check out and reproduce.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty — commit or stash before tagging" >&2
  git status --short >&2
  exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "warning: releasing from '$CURRENT_BRANCH', not 'main'" >&2
fi

HEAD_SHA="$(git rev-parse HEAD)"
PREV_TAG="$(git tag --list "$PACK-v*" --sort=-v:refname | head -n1 || true)"
RANGE_DESC="${PREV_TAG:+$PREV_TAG..}HEAD"

run() {
  if (( DRY_RUN )); then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    "$@"
  fi
}

cat <<EOF

About to release:
  pack       $PACK
  version    $VERSION
  tag        $TAG
  commit     $HEAD_SHA
  branch     $CURRENT_BRANCH
  workflow   .github/workflows/publish-$PACK.yml
  prev tag   ${PREV_TAG:-(none)}
  release    $([[ $CREATE_RELEASE -eq 1 ]] && echo "yes (gh release create)" || echo "no (tag only)")
  dry-run    $([[ $DRY_RUN -eq 1 ]] && echo "yes" || echo "no")

Commits since $RANGE_DESC:
EOF
git log --oneline "$RANGE_DESC" -- "$PACK" 2>/dev/null || echo "  (no commits found in pack path)"
echo

if (( ! DRY_RUN )); then
  read -r -p "Proceed? [y/N] " ANSWER
  case "$ANSWER" in
    y|Y|yes|YES) ;;
    *) echo "aborted" >&2; exit 1 ;;
  esac
fi

# Bump version in package.json and commit before tagging.
CURRENT_VERSION="$(python3 -c "import json,sys; print(json.load(open('$PACK_DIR/package.json'))['version'])")"
if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
  if (( DRY_RUN )); then
    echo "[dry-run] bump $PACK/package.json version: $CURRENT_VERSION -> $VERSION"
    echo "[dry-run] git add $PACK/package.json"
    echo "[dry-run] git commit -m \"chore($PACK): bump version to $VERSION\""
  else
    python3 - <<PYEOF
import json, pathlib
p = pathlib.Path("$PACK_DIR/package.json")
data = json.loads(p.read_text())
data["version"] = "$VERSION"
p.write_text(json.dumps(data, indent=2) + "\n")
PYEOF
    echo "+ bumped $PACK/package.json: $CURRENT_VERSION -> $VERSION"
    git add "$PACK_DIR/package.json"
    git commit -m "chore($PACK): bump version to $VERSION"
    git push origin "$CURRENT_BRANCH"
  fi
fi

run git tag -a "$TAG" -m "Release $TAG"
run git push origin "$TAG"

if (( CREATE_RELEASE )); then
  command -v gh >/dev/null || { echo "gh not found — skip --release or install GitHub CLI" >&2; exit 1; }
  if (( DRY_RUN )); then
    echo "[dry-run] gh release create $TAG --title \"$PACK $VERSION\" --generate-notes"
  else
    run gh release create "$TAG" \
      --title "$PACK $VERSION" \
      --generate-notes
  fi
fi

cat <<EOF

Tag pushed. Watch the publish workflow:
  gh run watch --workflow publish-$PACK.yml

When it completes, verify with:
  nono pull nolabs-ai/$PACK --force
EOF
