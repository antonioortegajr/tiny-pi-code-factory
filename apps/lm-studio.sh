#!/usr/bin/env bash
# LM Studio, headless. Installs the CLI, keeps models on the SSD, and runs the
# OpenAI-compatible server as a systemd service so it survives a reboot.
#
# The CLI subcommands have moved around between LM Studio releases, so this
# script checks what the installed `lms` actually supports rather than assuming,
# and tells you what to run by hand if something is missing.
APP_DESCRIPTION="headless LM Studio (lms CLI + server)"

LMS_PORT="${LMS_PORT:-1234}"
LMS_BIN="${LMS_BIN:-$TARGET_HOME/.lmstudio/bin/lms}"

# lms lives in the user's home, not on root's PATH.
_lms() { as_user "$LMS_BIN" "$@"; }

app_install() {
	need_sudo

	# --- install ------------------------------------------------------------
	if [ -x "$LMS_BIN" ]; then
		skip "lms already installed at $LMS_BIN"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install LM Studio via lmstudio.ai/install.sh"
	else
		log "installing LM Studio (arm64 headless)"
		# Installed as the user: it puts everything under ~/.lmstudio.
		as_user sh -c 'curl -fsSL https://lmstudio.ai/install.sh | bash' || {
			warn "install.sh failed"
			log "check https://lmstudio.ai/docs/app for the current Linux ARM64 instructions"
			return 1
		}
		changed "installed LM Studio"
	fi

	if [ ! -x "$LMS_BIN" ] && [ "$DRY_RUN" != "1" ]; then
		warn "lms not found at $LMS_BIN after install"
		log "if it landed elsewhere, set LMS_BIN in settings.local.env"
		return 1
	fi

	# Put lms on PATH for interactive shells.
	write_file "$TARGET_HOME/.config/my-pi5-setup/lmstudio.sh" <<'SH'
# Managed by my-pi5-setup (apps/lm-studio.sh). Sourced from ~/.bashrc.
[ -d "$HOME/.lmstudio/bin" ] && case ":$PATH:" in
	*":$HOME/.lmstudio/bin:"*) ;;
	*) export PATH="$HOME/.lmstudio/bin:$PATH" ;;
esac
SH
	ensure_line "$TARGET_HOME/.bashrc" \
		'[ -r "$HOME/.config/my-pi5-setup/lmstudio.sh" ] && . "$HOME/.config/my-pi5-setup/lmstudio.sh"' \
		'my-pi5-setup/lmstudio\.sh'

	# --- models on the SSD --------------------------------------------------
	# Same reasoning as everything else here: models are gigabytes and the boot
	# drive is a USB stick that gets wiped on the next reflash.
	local models_dir="" default_dir="$TARGET_HOME/.lmstudio/models"
	if [ -n "${LMSTUDIO_MODELS_DIR:-}" ]; then
		models_dir="$LMSTUDIO_MODELS_DIR"
	elif [ -n "${SSD_MOUNT_POINT:-}" ] && mountpoint -q "$SSD_MOUNT_POINT" 2>/dev/null; then
		models_dir="$SSD_MOUNT_POINT/lm-studio/models"
	fi

	if [ -z "$models_dir" ]; then
		warn "SSD not mounted at ${SSD_MOUNT_POINT:-unset}; models will land on the boot drive"
		log "run 'make storage' first, or set LMSTUDIO_MODELS_DIR in settings.local.env"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "point $default_dir at $models_dir"
	else
		ensure_dir "$models_dir"
		sudo chown -R "$TARGET_USER" "$models_dir" 2>/dev/null || true

		if [ -L "$default_dir" ] && [ "$(readlink "$default_dir")" = "$models_dir" ]; then
			skip "models directory already points at the SSD"
		elif [ -d "$default_dir" ] && [ ! -L "$default_dir" ] && [ -n "$(ls -A "$default_dir" 2>/dev/null)" ]; then
			# Never silently hide models that are already downloaded.
			warn "$default_dir already holds models"
			log "move them over yourself, then rerun:"
			log "  mv $default_dir/* $models_dir/ && rmdir $default_dir"
		else
			[ -d "$default_dir" ] && rmdir "$default_dir" 2>/dev/null || true
			ensure_dir "$(dirname "$default_dir")"
			as_user ln -sfn "$models_dir" "$default_dir"
			changed "models directory -> $models_dir"
		fi
	fi

	# --- service ------------------------------------------------------------
	if [ "$DRY_RUN" = "1" ]; then
		dry "install and start lmstudio-server.service on port $LMS_PORT"
	else
		# Lingering lets the service run without the user being logged in, which
		# is the whole point of headless.
		sudo loginctl enable-linger "$TARGET_USER" >/dev/null 2>&1 || true

		write_file /etc/systemd/system/lmstudio-server.service <<UNIT
# Managed by my-pi5-setup (apps/lm-studio.sh)
[Unit]
Description=LM Studio headless server
After=network-online.target
Wants=network-online.target
${SSD_MOUNT_POINT:+RequiresMountsFor=$SSD_MOUNT_POINT}

[Service]
Type=simple
User=$TARGET_USER
Environment="HOME=$TARGET_HOME"
ExecStartPre=-$LMS_BIN daemon up
ExecStart=$LMS_BIN server start --port $LMS_PORT
ExecStop=-$LMS_BIN server stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

		sudo systemctl daemon-reload
		if sudo systemctl enable --now lmstudio-server.service >/dev/null 2>&1; then
			changed "lmstudio-server running on port $LMS_PORT"
		else
			warn "lmstudio-server did not start"
			log "check:  systemctl status lmstudio-server  /  journalctl -u lmstudio-server"
			log "the CLI's flags move between releases; compare with:  $LMS_BIN server --help"
		fi
	fi

	# --- firewall -----------------------------------------------------------
	if has_cmd ufw && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
		if [ "${LMS_EXPOSE:-0}" = "1" ]; then
			if sudo ufw status 2>/dev/null | grep -q "^$LMS_PORT/tcp"; then
				skip "ufw already allows $LMS_PORT/tcp"
			else
				sudo ufw allow "$LMS_PORT/tcp" >/dev/null && changed "ufw allows $LMS_PORT/tcp"
			fi
		else
			log "API stays local. Set LMS_EXPOSE=1 to open $LMS_PORT to your LAN."
		fi
	fi

	# --- models -------------------------------------------------------------
	if [ -z "${LMS_MODEL:-}" ]; then
		log "LMS_MODEL is empty, no model downloaded. Find one with:  lms get --help"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "lms get $LMS_MODEL, then load it with context ${LMS_CONTEXT:-8192}"
	elif _lms ls 2>/dev/null | grep -q "${LMS_MODEL##*/}"; then
		skip "$LMS_MODEL already downloaded"
	else
		log "downloading $LMS_MODEL (gigabytes; several minutes on a Pi)"
		if _lms get "$LMS_MODEL" --yes 2>/dev/null || _lms get "$LMS_MODEL"; then
			changed "downloaded $LMS_MODEL"
		else
			warn "could not download $LMS_MODEL"
			log "check the name against:  lms get --help"
			return 1
		fi
	fi

	# --- load it -------------------------------------------------------------
	# Gemma 4 advertises a 256K context. Loading at that length on an 8 GB board
	# spends more memory on the KV cache than on the model, so pin it explicitly.
	if [ -n "${LMS_MODEL:-}" ] && [ "$DRY_RUN" != "1" ]; then
		if _lms ps 2>/dev/null | grep -q "${LMS_MODEL##*/}"; then
			skip "model already loaded"
		elif _lms load "$LMS_MODEL" --context-length "${LMS_CONTEXT:-8192}" --yes 2>/dev/null; then
			changed "loaded $LMS_MODEL at ${LMS_CONTEXT:-8192} context"
		elif _lms load "$LMS_MODEL" 2>/dev/null; then
			changed "loaded $LMS_MODEL (default context)"
			warn "could not pin the context length; check:  lms load --help"
		else
			warn "could not load $LMS_MODEL - the server is up, load it by hand"
			log "  lms load $LMS_MODEL --context-length ${LMS_CONTEXT:-8192}"
		fi
	fi

	# --- smoke test ----------------------------------------------------------
	# Cheap proof that the endpoint actually answers, rather than assuming it.
	if [ "$DRY_RUN" != "1" ] && has_cmd curl; then
		if curl -fsS --max-time 10 "http://127.0.0.1:$LMS_PORT/v1/models" >/dev/null 2>&1; then
			log "endpoint answered on port $LMS_PORT"
		else
			warn "no answer from http://127.0.0.1:$LMS_PORT/v1/models"
			log "check:  systemctl status lmstudio-server"
		fi
	fi

	log "OpenAI-compatible endpoint:  http://127.0.0.1:$LMS_PORT/v1"
}
