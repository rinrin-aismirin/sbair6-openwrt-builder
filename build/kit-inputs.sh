#!/bin/bash
# List the kit's build inputs that differ from the kit commit (uncommitted changes), one line per file:
# "<path> <sha256 of the working-tree file, or deleted>". Empty output: the build inputs are those of the commit.
# With --docs, list changed documentation files instead (same format); they do not affect the build.
# Usage: build/kit-inputs.sh KIT_DIR [--docs]
set -euo pipefail
K=$1
if [ "${2:-}" = --docs ]; then
	PATHS=(README.md docs)
else
	# Everything a build reads from the kit, except local/ (the owner's inputs, recorded separately).
	PATHS=(build.sh build config scripts/check_image.sh scripts/check_sysupgrade.py scripts/dtb_bootargs.py
		scripts/resign_boot.py feed docker
		fork.lock externals.lock stock-firmware.lock modem-files.lock)
fi
git -c safe.directory="$K" -C "$K" status --porcelain=v1 -z --untracked-files=all -- "${PATHS[@]}" |
	tr '\0' '\n' | sed -n 's/^.. //p' | LC_ALL=C sort -u | while IFS= read -r p; do
		if [ -f "$K/$p" ]; then
			echo "$p $(sha256sum < "$K/$p" | cut -d' ' -f1)"
		else
			echo "$p deleted"
		fi
	done
