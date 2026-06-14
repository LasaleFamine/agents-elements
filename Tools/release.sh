#!/bin/bash
#
# One-command release: bump the version, commit, tag, and push.
# CI (.github/workflows/build.yml) then builds the .app, zips it, and publishes
# the GitHub Release with notes (install header + CHANGELOG).
#
# Usage:
#   ./Tools/release.sh patch            # 1.0.0 -> 1.0.1
#   ./Tools/release.sh minor            # 1.0.0 -> 1.1.0
#   ./Tools/release.sh major            # 1.0.0 -> 2.0.0
#   ./Tools/release.sh 1.2.3            # explicit version
#
# Flags:
#   -y, --yes        skip the confirmation prompt
#   -n, --dry-run    show what would happen, change nothing
#       --allow-dirty allow a dirty working tree (the bump is committed anyway)
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "error: not in a git repo" >&2; exit 1; }

PLIST="Info.plist"
CHANGELOG="CHANGELOG.md"
ASSUME_YES=0
DRY_RUN=0
ALLOW_DIRTY=0
BUMP=""

for arg in "$@"; do
    case "$arg" in
        -y|--yes)      ASSUME_YES=1 ;;
        -n|--dry-run)  DRY_RUN=1 ;;
        --allow-dirty) ALLOW_DIRTY=1 ;;
        -h|--help)
            sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        major|minor|patch) BUMP="$arg" ;;
        [0-9]*.[0-9]*.[0-9]*) BUMP="$arg" ;;
        *) echo "error: unknown argument '$arg' (use patch|minor|major or X.Y.Z)" >&2; exit 1 ;;
    esac
done

[[ -n "$BUMP" ]] || { echo "usage: ./Tools/release.sh <patch|minor|major|X.Y.Z> [-y] [--dry-run]" >&2; exit 1; }

die() { echo "error: $*" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" ]] || echo "warning: not on 'main' (on '$BRANCH')"

if [[ "$ALLOW_DIRTY" -eq 0 && -n "$(git status --porcelain)" ]]; then
    die "working tree is dirty — commit/stash first, or pass --allow-dirty"
fi

command -v /usr/libexec/PlistBuddy >/dev/null || die "PlistBuddy not found"
CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
[[ "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "current version '$CURRENT' is not X.Y.Z"

# --- Compute the new version ----------------------------------------------
IFS='.' read -r MA MI PA <<< "$CURRENT"
case "$BUMP" in
    major) NEW="$((MA+1)).0.0" ;;
    minor) NEW="${MA}.$((MI+1)).0" ;;
    patch) NEW="${MA}.${MI}.$((PA+1))" ;;
    *)     NEW="$BUMP" ;;
esac
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "computed version '$NEW' is not X.Y.Z"
TAG="v${NEW}"

# refuse to go backwards or reuse a tag
[[ "$NEW" != "$CURRENT" ]] || die "new version equals current ($CURRENT)"
git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null && die "tag ${TAG} already exists locally"
if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    die "tag ${TAG} already exists on origin"
fi

# --- Plan ------------------------------------------------------------------
DATE="$(date +%F)"
echo "──────────────────────────────────────────"
echo " Release:   ${CURRENT}  ->  ${NEW}   (tag ${TAG})"
echo " Branch:    ${BRANCH}"
echo " Changelog: $(grep -q "## \[${NEW}\]" "$CHANGELOG" && echo "section exists" || echo "will add a '## [${NEW}] — ${DATE}' stub")"
echo " Then:      push ${BRANCH} + ${TAG}  ->  CI builds & publishes the release"
echo "──────────────────────────────────────────"

if [[ "$DRY_RUN" -eq 1 ]]; then echo "(dry run — nothing changed)"; exit 0; fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
    read -r -p "Proceed? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted."; exit 1; }
fi

# --- Apply -----------------------------------------------------------------
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW}" "$PLIST"

if ! grep -q "## \[${NEW}\]" "$CHANGELOG"; then
    # Insert a dated stub before the first existing "## [" section.
    awk -v v="$NEW" -v d="$DATE" '
        !done && /^## \[/ { print "## [" v "] — " d "\n\n- \n"; done=1 }
        { print }
    ' "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
    echo "note: added a CHANGELOG stub for ${NEW} — edit it now if you want real notes,"
    echo "      then re-run, or just continue (the release can be edited on GitHub later)."
fi

git add "$PLIST" "$CHANGELOG"
git commit -q -m "release: ${TAG}"
git tag -a "${TAG}" -m "Agents Elements ${NEW}"

echo "==> pushing ${BRANCH} and ${TAG}"
git push origin "${BRANCH}"
git push origin "${TAG}"

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
SLUG="$(echo "$REMOTE_URL" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
echo "──────────────────────────────────────────"
echo " ✓ ${TAG} pushed. CI is building the release now."
[[ -n "$SLUG" ]] && echo "   Actions:  https://github.com/${SLUG}/actions"
[[ -n "$SLUG" ]] && echo "   Release:  https://github.com/${SLUG}/releases/tag/${TAG}"
echo "──────────────────────────────────────────"
