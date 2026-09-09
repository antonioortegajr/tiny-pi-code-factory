#!/usr/bin/env bash
# Telegram trigger for the issue queue - tell the Pi a repo has work waiting.
#
# Not a chat bot: four fixed commands, no free-form path to the model. Long
# polling, so no public IP, no webhook and no TLS certificate - the Pi dials out.
APP_DESCRIPTION="Telegram trigger for the issue queue"

app_install() {
	need_sudo

	if [ -z "${TELEGRAM_TOKEN:-}" ]; then
		warn "TELEGRAM_TOKEN is not set"
		log "1. message @BotFather on Telegram, /newbot, copy the token"
		log "2. put it in settings.local.env (gitignored):"
		log "     TELEGRAM_TOKEN=123456:ABC..."
		log "     TELEGRAM_ALLOWED_IDS=<your chat id>   # @userinfobot tells you"
		log "3. rerun:  make app APP=telegram"
		return 0
	fi

	if [ -z "${TELEGRAM_ALLOWED_IDS:-}" ]; then
		# A bot token is a URL anyone can post to. Without an allowlist a stranger
		# who guesses the bot could drive an agent with write access to the repos.
		warn "TELEGRAM_ALLOWED_IDS is empty - refusing to install the service"
		log "without it, anyone who finds the bot could drive it"
		log "get your id from @userinfobot, then set it in settings.local.env"
		return 1
	fi

	ensure_dir "$TARGET_HOME/.local/bin"
	if [ "$DRY_RUN" = "1" ]; then
		dry "link and enable the telegram bridge"
	else
		as_user ln -sfn "$REPO_ROOT/bin/pi5-telegram" "$TARGET_HOME/.local/bin/pi5-telegram"
		chmod +x "$REPO_ROOT/bin/pi5-telegram" 2>/dev/null || true
	fi

	# The token goes in an EnvironmentFile rather than the unit: `systemctl show`
	# prints Environment= lines to any user on the box.
	local envfile="/etc/my-pi5-setup/telegram.env"
	{
		printf '# Managed by my-pi5-setup (apps/telegram.sh). Contains a secret.\n'
		printf 'TELEGRAM_TOKEN=%s\n' "$TELEGRAM_TOKEN"
		printf 'TELEGRAM_ALLOWED_IDS=%s\n' "$TELEGRAM_ALLOWED_IDS"
		printf 'TELEGRAM_ALLOW_WRITE=%s\n' "${TELEGRAM_ALLOW_WRITE:-0}"
		printf 'GITHUB_DIR=%s\n' "$GITHUB_DIR"
		printf 'TELEGRAM_REPOS=%s\n' "${TELEGRAM_REPOS:-}"
		printf 'TELEGRAM_PASSPHRASE=%s\n' "${TELEGRAM_PASSPHRASE:-}"
		printf 'AGENT_BASE_URL=%s\n' "${AGENT_BASE_URL:-http://127.0.0.1:11434/v1}"
	} | write_file "$envfile" 0600

	write_file /etc/systemd/system/pi5-telegram.service <<UNIT
# Managed by my-pi5-setup (apps/telegram.sh)
[Unit]
Description=Telegram bridge to the local model
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Environment="HOME=$TARGET_HOME"
EnvironmentFile=$envfile
ExecStart=$REPO_ROOT/bin/pi5-telegram
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

	if [ "$DRY_RUN" != "1" ]; then
		sudo systemctl daemon-reload
		if sudo systemctl enable --now pi5-telegram.service >/dev/null 2>&1; then
			changed "pi5-telegram running"
		else
			warn "pi5-telegram did not start"
			log "check:  journalctl -u pi5-telegram -n 30"
		fi
	fi

	log ""
	log "message your bot /help to check it"
	log "it takes four commands and nothing else - there is no chat path to the model"
	if [ -n "${TELEGRAM_PASSPHRASE:-}" ]; then
		log "passphrase required: prefix every message with it"
	fi
	if [ "${TELEGRAM_ALLOW_WRITE:-0}" = "1" ]; then
		warn "writes are ENABLED: /work <repo> can open draft PRs"
	else
		log "preview only. Set TELEGRAM_ALLOW_WRITE=1 to let /work actually do it."
	fi
}
