#!/usr/bin/env bash
# GitHub CLI, plus the local agent that drives it from the model.
#
# gh is the tool layer: the model asks for gh_issue_list, the agent runs `gh`
# with a fixed argv and hands the JSON back. No MCP server in the middle.
APP_DESCRIPTION="GitHub CLI + local agent"

app_install() {
	need_sudo

	# --- gh ------------------------------------------------------------------
	if has_cmd gh; then
		skip "gh already installed"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install the GitHub CLI"
	elif apt-cache show gh >/dev/null 2>&1; then
		apt_install gh
	else
		# Not in this release's archive - take the arm64 .deb from the release
		# page rather than adding another apt source for one package.
		local ver deb tmp
		ver="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
			| sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)"
		if [ -z "$ver" ]; then
			warn "could not determine the latest gh release"
			log "install it by hand from https://github.com/cli/cli/releases"
			return 1
		fi
		deb="gh_${ver}_linux_arm64.deb"
		tmp="$(mktemp -d)"
		log "downloading gh $ver (arm64)"
		if curl -fsSL -o "$tmp/$deb" \
			"https://github.com/cli/cli/releases/download/v${ver}/${deb}"; then
			sudo dpkg -i "$tmp/$deb" >/dev/null 2>&1 || sudo apt-get -f install -y -qq
			changed "installed gh $ver"
		else
			warn "download failed for $deb"
			rm -rf "$tmp"; return 1
		fi
		rm -rf "$tmp"
	fi

	# --- the agent -----------------------------------------------------------
	# A symlink, not a copy, so editing the repo copy takes effect immediately.
	local bindir="$TARGET_HOME/.local/bin"
	ensure_dir "$bindir"
	if [ "$DRY_RUN" = "1" ]; then
		dry "link $bindir/pi5-agent -> $REPO_ROOT/bin/pi5-agent"
	else
		as_user ln -sfn "$REPO_ROOT/bin/pi5-agent" "$bindir/pi5-agent"
		chmod +x "$REPO_ROOT/bin/pi5-agent" 2>/dev/null || true
		changed "linked pi5-agent into $bindir"
	fi

	ensure_line "$TARGET_HOME/.bashrc" \
		'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac' \
		'HOME/\.local/bin'

	# --- auth ----------------------------------------------------------------
	if [ "$DRY_RUN" != "1" ] && has_cmd gh; then
		if as_user gh auth status >/dev/null 2>&1; then
			skip "gh is already authenticated"
			# The agent pushes branches without a terminal to prompt at, so git
			# needs a credential helper. gh already holds a usable token.
			if as_user git config --global --get-regexp 'credential.*helper' \
				| grep -q 'gh auth git-credential'; then
				skip "git already uses gh for credentials"
			else
				as_user gh auth setup-git && changed "git now uses gh for credentials" \
					|| warn "gh auth setup-git failed; pushes may prompt"
			fi
		else
			log "gh is not authenticated yet. Run this yourself when convenient:"
			log "  gh auth login"
			log ""
			log "For an agent, prefer a fine-grained token with read-only access to"
			log "the repos you care about, rather than full account scope:"
			log "  gh auth login --with-token < token.txt"
			log ""
			log "then run this, or the agent cannot push branches:"
			log "  gh auth setup-git"
		fi
	fi

	log ""
	log "check that the model can actually call tools:"
	log "  pi5-agent --selftest"
	log "then, in a checkout:"
	log "  pi5-agent 'summarise my open issues'"
}
