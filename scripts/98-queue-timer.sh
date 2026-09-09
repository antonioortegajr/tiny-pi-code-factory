#!/usr/bin/env bash
# Poll GitHub for agent:queued issues on a timer, so you can label an issue and
# walk away.
#
#   make queue-timer              install and start it
#   make queue-timer ARGS=off     stop and disable it
#
# A timer rather than cron: systemd will not start a second run while one is
# still going, which matters when a single issue can take ten minutes, and the
# output lands in the journal instead of a stray log file.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected
need_sudo

if [ "${1:-on}" = "off" ]; then
	step "Disabling the queue timer"
	if [ "$DRY_RUN" != "1" ]; then
		sudo systemctl disable --now pi5-queue.timer >/dev/null 2>&1 \
			&& changed "pi5-queue.timer stopped" || skip "was not enabled"
	fi
	summary "queue-timer"; exit 0
fi

step "Queue timer"

# Autonomous writing is opt-in. Nothing here should start doing work on its own
# because a default said so.
if [ "${QUEUE_AUTO:-0}" != "1" ]; then
	warn "QUEUE_AUTO is not 1, refusing to install"
	log "This runs the agent unattended and opens pull requests without you"
	log "watching. Enable it deliberately in settings.local.env:"
	log "  QUEUE_AUTO=1"
	exit 1
fi

has_cmd gh || die "gh is not installed (make app APP=gh)"
if ! as_user gh auth status >/dev/null 2>&1; then
	die "gh is not authenticated - run: gh auth login && gh auth setup-git"
fi

chmod +x "$REPO_ROOT/bin/pi5-queue-all" 2>/dev/null || true

# Telegram credentials, if the bridge is installed, so a finished run can say so.
env_files="/etc/my-pi5-setup/queue.env"
{
	printf '# Managed by my-pi5-setup (scripts/98-queue-timer.sh)\n'
	printf 'GITHUB_DIR=%s\n' "$GITHUB_DIR"
	printf 'QUEUE_REPOS=%s\n' "${QUEUE_REPOS:-}"
	printf 'AGENT_LABEL=%s\n' "${AGENT_LABEL:-agent:queued}"
	printf 'AGENT_BASE_URL=%s\n' "${AGENT_BASE_URL:-http://127.0.0.1:11434/v1}"
} | write_file "$env_files" 0644

telegram_env=""
[ -f /etc/my-pi5-setup/telegram.env ] && telegram_env="EnvironmentFile=-/etc/my-pi5-setup/telegram.env"

write_file /etc/systemd/system/pi5-queue.service <<UNIT
# Managed by my-pi5-setup (scripts/98-queue-timer.sh)
[Unit]
Description=Work agent:queued GitHub issues with the local model
After=ollama.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$TARGET_USER
Environment="HOME=$TARGET_HOME"
EnvironmentFile=$env_files
$telegram_env
ExecStart=$REPO_ROOT/bin/pi5-queue-all
# One issue can take ten minutes on this hardware; do not shoot it halfway.
TimeoutStartSec=3600
UNIT

write_file /etc/systemd/system/pi5-queue.timer <<UNIT
# Managed by my-pi5-setup (scripts/98-queue-timer.sh)
[Unit]
Description=Poll GitHub for agent:queued issues

[Timer]
OnBootSec=5min
OnUnitActiveSec=${QUEUE_INTERVAL:-15min}
# Catch up after a reboot rather than waiting a full interval.
Persistent=true
Unit=pi5-queue.service

[Install]
WantedBy=timers.target
UNIT

if [ "$DRY_RUN" != "1" ]; then
	sudo systemctl daemon-reload
	sudo systemctl enable --now pi5-queue.timer >/dev/null 2>&1 \
		&& changed "polling every ${QUEUE_INTERVAL:-15min}" \
		|| warn "could not enable pi5-queue.timer"
fi

log ""
log "label an issue '${AGENT_LABEL:-agent:queued}' and it will be picked up."
log "  systemctl list-timers pi5-queue.timer     when it next runs"
log "  journalctl -u pi5-queue -f                watch it work"
log "  systemctl start pi5-queue                 run one cycle now"
log "  make queue-timer ARGS=off                 stop it"
summary "queue-timer"
