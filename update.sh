#!/usr/bin/env bash
# Bump all *-bin packages to the latest GitHub release.
# Usage: ./update.sh [--push]
#   --push  also commit + push each changed package to AUR (needs SSH key).
set -euo pipefail

cd "$(dirname "$0")"
PUSH=0
[[ "${1:-}" == "--push" ]] && PUSH=1

for dir in *-bin; do
	[[ -d "$dir" ]] || continue
	pkgfile="$dir/PKGBUILD"
	_pkgname="${dir%-bin}"
	url="https://github.com/storytold/$_pkgname"

	tag=$(curl -fsSL "https://api.github.com/repos/storytold/$_pkgname/releases/latest" \
		| python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')
	latest="${tag#v}"
	current=$(grep -E '^pkgver=' "$pkgfile" | cut -d= -f2)

	if [[ "$latest" == "$current" ]]; then
		printf '%s: up to date (%s)\n' "$dir" "$current"
		continue
	fi

	printf '%s: %s -> %s\n' "$dir" "$current" "$latest"
	sums=$(curl -fsSL "$url/releases/download/$tag/SHA256SUMS.txt")
	getsum() { grep -E "  $_pkgname-$latest-linux-$1\.tar\.gz$" <<<"$sums" | cut -d' ' -f1; }
	sha_x86=$(getsum x86_64)
	sha_arm=$(getsum aarch64)
	[[ -n "$sha_x86" && -n "$sha_arm" ]] || { echo "$dir: hashes missing in SHA256SUMS.txt" >&2; exit 1; }

	sed -i -e "s/^pkgver=.*/pkgver=$latest/" -e 's/^pkgrel=.*/pkgrel=1/' "$pkgfile"
	sed -i -e "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('$sha_x86')/" \
		-e "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('$sha_arm')/" "$pkgfile"
	(cd "$dir" && makepkg --printsrcinfo > .SRCINFO)

	if (( PUSH )); then
		work=$(mktemp -d)
		git clone -q "ssh://aur@aur.archlinux.org/$dir.git" "$work/$dir"
		cp "$dir/PKGBUILD" "$dir/.SRCINFO" "$work/$dir/"
		git -C "$work/$dir" add PKGBUILD .SRCINFO
		if git -C "$work/$dir" diff --cached --quiet; then
			rm -rf "$work"
			printf '%s: AUR already has %s-1; no push needed\n' "$dir" "$latest"
			continue
		fi
		git -C "$work/$dir" -c user.name="${GIT_AUTHOR_NAME:-aur}" -c user.email="${GIT_AUTHOR_EMAIL:-aur@localhost}" \
			commit -qm "Update to $latest-1"
		git -C "$work/$dir" push -q
		rm -rf "$work"
		printf '%s: pushed %s-1 to AUR\n' "$dir" "$latest"
	fi
done
