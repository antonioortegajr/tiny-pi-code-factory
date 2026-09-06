#!/usr/bin/env bash
# apt helpers.

_APT_UPDATED=0

apt_update_once() {
	[ "$_APT_UPDATED" = "1" ] && return 0
	_APT_UPDATED=1
	if [ "$DRY_RUN" = "1" ]; then dry "apt-get update"; return 0; fi
	log "apt-get update"
	sudo apt-get update -qq
}

pkg_installed() {
	dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null | grep -q '^installed$'
}

# apt_install pkg... - installs only what is missing, in one batch.
apt_install() {
	local missing=() p
	for p in "$@"; do
		if pkg_installed "$p"; then skip "$p already installed"; else missing+=("$p"); fi
	done
	[ ${#missing[@]} -eq 0 ] && return 0
	if [ "$DRY_RUN" = "1" ]; then dry "apt-get install ${missing[*]}"; return 0; fi
	apt_update_once
	log "installing: ${missing[*]}"
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
	for p in "${missing[@]}"; do changed "installed $p"; done
}

# Install a package only if it exists in the archive; some package names differ
# between Bookworm and Trixie, and a missing optional extra should not abort.
apt_install_optional() {
	local p avail=()
	for p in "$@"; do
		if pkg_installed "$p"; then skip "$p already installed"; continue; fi
		if apt-cache show "$p" >/dev/null 2>&1; then avail+=("$p")
		else warn "package not available on $(os_codename): $p"; fi
	done
	[ ${#avail[@]} -gt 0 ] && apt_install "${avail[@]}"
	return 0
}

# Docker, installed on demand. Lives here rather than in 40-dev.sh because apps
# need it too, and an app should not silently fail because a flag was off.
ensure_docker() {
	if has_cmd docker; then
		skip "docker already installed"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install docker via get.docker.com"
		return 0
	else
		log "installing docker (get.docker.com)"
		curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
		sudo sh /tmp/get-docker.sh
		rm -f /tmp/get-docker.sh
		changed "installed docker"
	fi
	# Without this every docker call needs sudo.
	if [ "$DRY_RUN" != "1" ] && ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
		sudo usermod -aG docker "$TARGET_USER"
		changed "added $TARGET_USER to the docker group"
		log "log out and back in before running docker without sudo"
	fi
}
