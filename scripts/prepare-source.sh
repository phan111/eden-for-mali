#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Clone Eden at the pinned revision and apply the Mali / Galaxy Tab S11 patch
# series on top of it.
#
# Usage: scripts/prepare-source.sh [target-dir]
#
# Environment:
#   EDEN_REMOTE   "mirror" (default) or "upstream". Upstream is git.eden-emu.dev;
#                 use the mirror when that host is unreachable from your network.
#   EDEN_COMMIT   Override the pinned commit (accepts any ref the remote serves).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-${REPO_ROOT}/eden-src}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/eden-source.pin"

case "${EDEN_REMOTE:-mirror}" in
    upstream) REMOTE="${EDEN_UPSTREAM_URL}" ;;
    mirror)   REMOTE="${EDEN_MIRROR_URL}" ;;
    *) echo "!! EDEN_REMOTE must be 'mirror' or 'upstream'" >&2; exit 2 ;;
esac

COMMIT="${EDEN_COMMIT}"

echo "-- Eden remote : ${REMOTE}"
echo "-- Eden commit : ${COMMIT}"
echo "-- Target dir  : ${TARGET}"

if [ -e "${TARGET}" ]; then
    echo "!! ${TARGET} already exists. Remove it or pass another target directory." >&2
    exit 1
fi

# Eden's dependencies are fetched by CPM at configure time, so a shallow clone of
# a single commit is enough to build from.
mkdir -p "${TARGET}"
git -C "${TARGET}" init -q
git -C "${TARGET}" remote add origin "${REMOTE}"
echo "-- fetching (this pulls a few hundred MB)..."
git -C "${TARGET}" fetch -q --depth 1 origin "${COMMIT}"
git -C "${TARGET}" checkout -q FETCH_HEAD

# git am needs an identity; keep it local to this clone.
git -C "${TARGET}" config user.name "eden-for-mali"
git -C "${TARGET}" config user.email "eden-for-mali@localhost"

echo "-- applying patch series"
while read -r patch; do
    case "${patch}" in ''|\#*) continue ;; esac
    echo "   * ${patch}"
    git -C "${TARGET}" am --keep-non-patch "${REPO_ROOT}/patches/${patch}"
done < "${REPO_ROOT}/patches/series"

echo
echo "-- Done. Patched Eden tree is at ${TARGET}"
git -C "${TARGET}" log --oneline -n "$(grep -cvE '^\s*(#|$)' "${REPO_ROOT}/patches/series")"
