#!/usr/bin/env bash
# Dark theme for the terminal emulator, the shell, and CLI tools.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

step "Dark theme: terminal and CLI"

# --- LXTerminal (the terminal Raspberry Pi OS ships) -----------------------
# Colour keys only: this file also holds geometry and scrollback, which are the
# user's business.
lxt="$TARGET_HOME/.config/lxterminal/lxterminal.conf"
if has_cmd lxterminal || [ -f "$lxt" ]; then
	ini_set "$lxt" general bgcolor 'rgb(28,28,28)'
	ini_set "$lxt" general fgcolor 'rgb(216,216,216)'
	ini_set "$lxt" general disallowbold 'false'
	ini_set "$lxt" general cursorblinks 'false'
	# Bind copy/paste explicitly. They are Ctrl+Shift+C/V rather than Ctrl+C/V
	# because Ctrl+C is SIGINT and cannot be rebound. Capitals matter here.
	ini_set "$lxt" shortcut copy '<CTRL><SHIFT>C'
	ini_set "$lxt" shortcut paste '<CTRL><SHIFT>V'

	i=0
	for c in '28,28,28' '224,85,97' '140,194,101' '209,143,82' \
	         '74,165,240' '193,98,222' '66,179,194' '216,216,216' \
	         '107,107,107' '255,97,110' '165,224,117' '240,164,93' \
	         '77,196,255' '222,115,255' '76,209,224' '242,242,242'; do
		ini_set "$lxt" general "palette_color_$i" "rgb($c)"
		i=$((i + 1))
	done
else
	skip "lxterminal not installed"
fi

# --- Shell -----------------------------------------------------------------
install_config shell/dircolors.dark "$TARGET_HOME/.config/dircolors"

# Everything shell-side lives in one sourced file, so this stays a single line in
# .bashrc and re-running the script never duplicates anything.
snippet="$TARGET_HOME/.config/my-pi5-setup/shell-dark.sh"
write_file "$snippet" <<'SH'
# Managed by my-pi5-setup (scripts/31-dark-terminal.sh). Sourced from ~/.bashrc.

# Directory colours that are legible on a near-black background.
if [ -r "$HOME/.config/dircolors" ] && command -v dircolors >/dev/null 2>&1; then
	eval "$(dircolors -b "$HOME/.config/dircolors")"
fi

# Tell every well-behaved TUI that the background is dark.
export COLORFGBG="15;0"

command -v bat >/dev/null 2>&1 && export BAT_THEME="ansi"
command -v batcat >/dev/null 2>&1 && export BAT_THEME="ansi"

if command -v fzf >/dev/null 2>&1; then
	export FZF_DEFAULT_OPTS="--color=bg+:#262626,bg:#1c1c1c,spinner:#c51a4a,hl:#4aa5f0
--color=fg:#d8d8d8,header:#4aa5f0,info:#8cc265,pointer:#c51a4a
--color=marker:#8cc265,fg+:#f2f2f2,prompt:#c51a4a,hl+:#4dc4ff"
fi
SH

ensure_line "$TARGET_HOME/.bashrc" \
	'[ -r "$HOME/.config/my-pi5-setup/shell-dark.sh" ] && . "$HOME/.config/my-pi5-setup/shell-dark.sh"' \
	'my-pi5-setup/shell-dark\.sh'

# --- tmux ------------------------------------------------------------------
if has_cmd tmux; then
	write_file "$TARGET_HOME/.config/tmux/dark.conf" <<'TMUX'
# Managed by my-pi5-setup (scripts/31-dark-terminal.sh)
set -g status-style "bg=#262626,fg=#d8d8d8"
set -g window-status-current-style "bg=#c51a4a,fg=#ffffff,bold"
set -g pane-border-style "fg=#2e2e2e"
set -g pane-active-border-style "fg=#c51a4a"
set -g message-style "bg=#262626,fg=#f2f2f2"
TMUX
	ensure_line "$TARGET_HOME/.tmux.conf" \
		'source-file -q ~/.config/tmux/dark.conf' \
		'source-file .*tmux/dark\.conf'
else
	skip "tmux not installed"
fi

# --- Neovim ----------------------------------------------------------------
# plugin/ is auto-sourced, so this adds dark without touching an existing config.
if has_cmd nvim; then
	write_file "$TARGET_HOME/.config/nvim/plugin/dark.lua" <<'LUA'
-- Managed by my-pi5-setup (scripts/31-dark-terminal.sh)
vim.opt.background = "dark"
vim.opt.termguicolors = true
LUA
else
	skip "neovim not installed"
fi

# --- git-delta -------------------------------------------------------------
if has_cmd delta; then
	as_user git config --global delta.dark true || warn "could not set git delta.dark"
	as_user git config --global delta.syntax-theme "ansi" || true
	log "git-delta set to dark"
fi

summary "dark-terminal"
