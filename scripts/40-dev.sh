#!/usr/bin/env bash
# Development environment: git identity, an SSH key, and the optional toolchains.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected
need_sudo

step "Developer packages"
# shellcheck disable=SC2086
apt_install_optional $DEV_PACKAGES

step "git"
if [ -n "$GIT_USER_NAME" ]; then
	if [ "$(as_user git config --global --get user.name 2>/dev/null || true)" = "$GIT_USER_NAME" ]; then
		skip "git user.name already set"
	else
		run_change as_user git config --global user.name "$GIT_USER_NAME"
	fi
fi
if [ -n "$GIT_USER_EMAIL" ]; then
	if [ "$(as_user git config --global --get user.email 2>/dev/null || true)" = "$GIT_USER_EMAIL" ]; then
		skip "git user.email already set"
	else
		run_change as_user git config --global user.email "$GIT_USER_EMAIL"
	fi
fi
as_user git config --global init.defaultBranch main || true
as_user git config --global pull.rebase false || true

step "Shell conveniences"

# The repo directory is bind-mounted from the SSD, but create it anyway so the
# function still works on a machine where the SSD is absent.
ensure_dir "$GITHUB_DIR"

# The path is injected as one assignment; the rest of the snippet is a quoted
# heredoc so nothing in it expands at generation time.
{
	printf '# Managed by my-pi5-setup (scripts/40-dev.sh). Sourced from ~/.bashrc.\n'
	printf 'export GITHUB_DIR="%s"\n\n' "$GITHUB_DIR"
	cat <<'ALIASES'
# 'github' jumps to the repo directory; 'github <name>' goes straight into one.
# A function rather than an alias so it can take that argument.
github() {
	local base="${GITHUB_DIR:-$HOME/GitHub}"
	if [ ! -d "$base" ]; then
		printf '%s does not exist\n' "$base" >&2
		return 1
	fi
	if [ -n "$1" ] && [ -d "$base/$1" ]; then
		cd "$base/$1" || return 1
	else
		[ -n "$1" ] && printf 'no such repo: %s\n' "$1" >&2
		cd "$base" || return 1
	fi
}

_github_complete() {
	local base="${GITHUB_DIR:-$HOME/GitHub}"
	local cur="${COMP_WORDS[COMP_CWORD]}"
	mapfile -t COMPREPLY < <(compgen -W "$(ls -1 "$base" 2>/dev/null)" -- "$cur")
}
complete -F _github_complete github
ALIASES
} | write_file "$TARGET_HOME/.config/my-pi5-setup/shell-aliases.sh"

ensure_line "$TARGET_HOME/.bashrc" \
	'[ -r "$HOME/.config/my-pi5-setup/shell-aliases.sh" ] && . "$HOME/.config/my-pi5-setup/shell-aliases.sh"' \
	'my-pi5-setup/shell-aliases\.sh'

step "SSH key"
key="$TARGET_HOME/.ssh/id_ed25519"
if [ -f "$key" ]; then
	skip "$key already exists"
elif [ "$DRY_RUN" = "1" ]; then
	dry "generate ssh key $key"
else
	ensure_dir "$TARGET_HOME/.ssh"
	chmod 700 "$TARGET_HOME/.ssh" 2>/dev/null || sudo chmod 700 "$TARGET_HOME/.ssh"
	as_user ssh-keygen -t ed25519 -N '' -C "$TARGET_USER@$PI_HOSTNAME" -f "$key"
	changed "generated $key"
	log "public key (add to GitHub if you want to push from the Pi):"
	printf '\n'; cat "$key.pub"; printf '\n'
fi

step "Optional toolchains"

if [ "${INSTALL_UV:-0}" = "1" ]; then
	if as_user test -x "$TARGET_HOME/.local/bin/uv"; then
		skip "uv already installed"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install uv"
	else
		# Installer script is fetched over TLS from Astral and run as the user, not root.
		as_user sh -c 'curl -fsSL https://astral.sh/uv/install.sh | sh' \
			&& changed "installed uv" || warn "uv install failed"
	fi
else
	skip "uv disabled"
fi

if [ "${INSTALL_NODE:-0}" = "1" ]; then
	nvm_dir="$TARGET_HOME/.nvm"
	if [ -d "$nvm_dir" ]; then
		skip "nvm already installed"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install nvm and node $NODE_VERSION"
	else
		as_user sh -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash' \
			&& changed "installed nvm" || warn "nvm install failed"
		as_user bash -lc ". \"$nvm_dir/nvm.sh\" && nvm install '$NODE_VERSION'" \
			|| warn "node install failed"
	fi
else
	skip "node disabled"
fi

if [ "${INSTALL_DOCKER:-0}" = "1" ]; then
	ensure_docker
else
	skip "docker disabled (apps that need it will install it on demand)"
fi

summary "dev"
