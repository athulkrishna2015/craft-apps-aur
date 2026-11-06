#!/usr/bin/env bash
# Bump all *-bin packages to the latest GitHub release.
# Usage: ./update.sh [--push]
#   --push  also commit + push each changed package to AUR (needs SSH key).
set -euo pipefail

cd "$(dirname "$0")"
PUSH=0
[[ "${1:-}" == "--push" ]] && PUSH=1

failed=()

for dir in *-bin; do
	[[ -d "$dir" ]] || continue
	pkgfile="$dir/PKGBUILD"
	_pkgname="${dir%-bin}"
	# Release artifacts can be named after the binary rather than the repo
	# (e.g. craft-launcher ships artcraft-launcher-*). PKGBUILD declares _distname
	# to override; it defaults to the repo name.
	_distname=$(grep -E '^_distname=' "$pkgfile" | cut -d= -f2- | tr -d "'\"" || true)
	_distname="${_distname:-$_pkgname}"
	url="https://github.com/storytold/$_pkgname"

	# Authenticate GitHub API calls when a token is available. Unauthenticated
	# requests are capped at 60/hour per IP and GitHub-hosted runners share IPs,
	# so CI intermittently gets 403s without this.
	api_args=(--retry 3 --retry-delay 5 -H "Accept: application/vnd.github+json")
	if [[ -n "${GITHUB_TOKEN:-}" ]]; then
		api_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
	fi

	release_json=$(curl -fsSL "${api_args[@]}" \
		"https://api.github.com/repos/storytold/$_pkgname/releases/latest") \
		|| { echo "$dir: GitHub API request failed (rate limited? set GITHUB_TOKEN)" >&2; failed+=("$dir"); continue; }
	tag=$(python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])' <<<"$release_json") \
		|| { echo "$dir: could not parse latest release tag" >&2; failed+=("$dir"); continue; }
	latest="${tag#v}"
	current=$(grep -E '^pkgver=' "$pkgfile" | cut -d= -f2)
	pkgrel=$(grep -E '^pkgrel=' "$pkgfile" | cut -d= -f2)

	if [[ "$latest" == "$current" ]]; then
		printf '%s: up to date (%s)\n' "$dir" "$current"
	else
		printf '%s: %s -> %s\n' "$dir" "$current" "$latest"
		sums=$(curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
			"$url/releases/download/$tag/SHA256SUMS.txt")
		getsum() { grep -E "  $_distname-$latest-linux-$1\.tar\.gz$" <<<"$sums" | cut -d' ' -f1; }
		sha_x86=$(getsum x86_64)
		sha_arm=$(getsum aarch64)
		if [[ -z "$sha_x86" || -z "$sha_arm" ]]; then
			echo "$dir: hashes missing in SHA256SUMS.txt" >&2
			failed+=("$dir")
			continue
		fi

		if ! sed -i -e "s/^pkgver=.*/pkgver=$latest/" -e 's/^pkgrel=.*/pkgrel=1/' "$pkgfile"; then
			echo "$dir: failed to rewrite pkgver" >&2; failed+=("$dir"); continue
		fi
		if ! sed -i -e "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('$sha_x86')/" \
			-e "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('$sha_arm')/" "$pkgfile"; then
			echo "$dir: failed to rewrite sha256sums" >&2; failed+=("$dir"); continue
		fi
		if ! (cd "$dir" && makepkg --printsrcinfo > .SRCINFO); then
			echo "$dir: makepkg failed" >&2; failed+=("$dir"); continue
		fi
	fi

	if (( PUSH )); then
		# Avoid rapid-fire SSH sessions to AUR from the same CI runner IP.
		# A small jittered delay between repos reduces chance of the AUR
		# SSH daemon dropping connections.
		sleep "${AUR_CLONE_DELAY:-2}.$((RANDOM % 90 + 10))"
		work=$(mktemp -d)
		clone_ok=0
		for attempt in 1 2 3; do
			if git clone -q "ssh://aur@aur.archlinux.org/$dir.git" "$work/$dir" 2>/tmp/clone-err; then
				clone_ok=1
				break
			fi
			# Exponential backoff: 5s, 10s, 15s after attempts 1 and 2.
			[[ $attempt -lt 3 ]] && sleep $((attempt * 5))
		done
		if (( ! clone_ok )); then
			echo "$dir: AUR clone failed: $(cat /tmp/clone-err)" >&2
			rm -rf "$work"
			failed+=("$dir")
			continue
		fi
		cp "$dir/PKGBUILD" "$dir/.SRCINFO" "$work/$dir/"
		git -C "$work/$dir" add PKGBUILD .SRCINFO
		if git -C "$work/$dir" diff --cached --quiet; then
			rm -rf "$work"
			printf '%s: AUR already has %s-%s; no push needed\n' "$dir" "$latest" "$pkgrel"
			continue
		fi
		# Re-read pkgrel after any sed bump above so the message matches.
		pkgrel=$(grep -E '^pkgrel=' "$pkgfile" | cut -d= -f2)
		git -C "$work/$dir" -c user.name="${GIT_AUTHOR_NAME:-aur}" -c user.email="${GIT_AUTHOR_EMAIL:-aur@localhost}" \
			commit -qm "Update to $latest-$pkgrel"
		for attempt in 1 2 3; do
			if git -C "$work/$dir" push -q; then
				break
			fi
			[[ $attempt -lt 3 ]] && sleep $((attempt * 5))
		done || { echo "$dir: AUR push failed" >&2; failed+=("$dir"); }
		rm -rf "$work"
		printf '%s: pushed %s-%s to AUR\n' "$dir" "$latest" "$pkgrel"
	fi
done

if (( ${#failed[@]} )); then
	echo "FAILED packages: ${failed[*]}" >&2
	exit 1
fi
