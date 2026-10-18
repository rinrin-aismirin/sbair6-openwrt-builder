#!/bin/bash
# Fetch the LG6851F files listed in externals.lock at the pinned commit (sparse, blobless) and verify every hash.
# Usage: build/fetch-externals.sh LOCKFILE DEST
set -euo pipefail
LOCK=$1 DEST=$2
. "$LOCK"
[ -d "$DEST/.git" ] || { git init -q "$DEST"; git -C "$DEST" remote add origin "$LG6851F_REPO"; }
paths=$(echo "$LG6851F_FILES" | awk 'NF == 2 { print "/" $1 }')
git -C "$DEST" sparse-checkout set --no-cone $paths "/$LG6851F_SIGN_TOOL_DIR/"
git -C "$DEST" fetch -q --depth 1 --filter=blob:none origin "$LG6851F_COMMIT"
git -C "$DEST" -c advice.detachedHead=false checkout -q -f FETCH_HEAD
[ "$(git -C "$DEST" rev-parse HEAD)" = "$LG6851F_COMMIT" ] || { echo "externals: wrong commit"; exit 1; }
[ "$(git -C "$DEST" rev-parse "HEAD:$LG6851F_SIGN_TOOL_DIR")" = "$LG6851F_SIGN_TOOL_TREE" ] || { echo "externals: sign tool tree differs"; exit 1; }
echo "$LG6851F_FILES" | awk 'NF == 2' | while read -r p h; do echo "$h  $DEST/$p"; done | sha256sum -c --quiet - ||
	{ echo "externals: hash mismatch"; exit 1; }
echo "externals OK: $LG6851F_REPO @ $LG6851F_COMMIT"
