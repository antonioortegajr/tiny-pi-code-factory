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

# systemd does not read a login profile, so the service gets a bare PATH and
# anything installed under $HOME is invisible to it. opencode installs to
# ~/.opencode/bin, so the queue's escalation - try opencode when the built-in
# loop opens no PR - was silently skipped on every failure: shutil.which found
# nothing and the escalation branch never ran. Resolve it as the user, once, at
# install time, and put its directory on the service's PATH.
service_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# Not `bash -lc 'command -v opencode'`: a login shell reads ~/.profile, while
# opencode's installer appends its PATH line to ~/.bashrc, which returns early
# when non-interactive. That lookup finds nothing on a machine where the binary
# is plainly there. Probe the install locations instead, then fall back to
# whatever is already on PATH.
opencode_bin=""
for cand in "$TARGET_HOME/.opencode/bin/opencode" \
            "$TARGET_HOME/.local/bin/opencode" \
            "$TARGET_HOME/.bun/bin/opencode" \
            "$TARGET_HOME/.npm-global/bin/opencode" \
            "/usr/local/bin/opencode" \
            "/opt/opencode/bin/opencode"; do
	[ -x "$cand" ] && { opencode_bin="$cand"; break; }
done
[ -n "$opencode_bin" ] || opencode_bin="$(command -v opencode 2>/dev/null || true)"
if [ -n "$opencode_bin" ]; then
	opencode_dir="$(dirname "$opencode_bin")"
	case ":$service_path:" in
		*":$opencode_dir:"*) ;;
		*) service_path="$opencode_dir:$service_path" ;;
	esac
	log "opencode: $opencode_bin"
else
	warn "opencode not found; the queue will not escalate a failed issue"
fi

{
	printf '# Managed by my-pi5-setup (scripts/98-queue-timer.sh)\n'
	printf 'PATH=%s\n' "$service_path"
	printf 'GITHUB_DIR=%s\n' "$GITHUB_DIR"
	printf 'QUEUE_REPOS=%s\n' "${QUEUE_REPOS:-}"
	printf 'QUEUE_DISCOVER=%s\n' "${QUEUE_DISCOVER:-0}"
	printf 'QUEUE_OWNER=%s\n' "${QUEUE_OWNER:-}"
	printf 'QUEUE_TOPIC=%s\n' "${QUEUE_TOPIC:-}"
	printf 'AGENT_LABEL=%s\n' "${AGENT_LABEL:-agent:queued}"
	printf 'AGENT_BASE_URL=%s\n' "${AGENT_BASE_URL:-http://127.0.0.1:11434/v1}"
	# Only variables that are actually set. An EnvironmentFile line of
	# 'AGENT_MAX_TURNS=' sets the variable to the empty string, which is not the
	# same as unset: os.environ.get returns "" instead of the default, and
	# int("") raises. Empty lines here would crash pi5-agent on every run, and
	# quietly flip AGENT_ESCALATE and AGENT_PR_CLOSES off into the bargain.
	for _v in AGENT_MODEL_ID AGENT_MAX_TURNS AGENT_MAX_TOOL_CHARS \
	          AGENT_READ_LINES AGENT_TIMEOUT AGENT_ESCALATE \
	          AGENT_PR_DRAFT AGENT_PR_CLOSES AGENT_TOOL_MODE \
	          AGENT_GLOBAL_INSTRUCTIONS; do
		[ -n "${!_v:-}" ] && printf '%s=%s\n' "$_v" "${!_v}"
	done
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
if [ "${QUEUE_DISCOVER:-0}" = "1" ]; then
	if [ -n "${QUEUE_TOPIC:-}" ]; then
		log "discovery on: repos with the '$QUEUE_TOPIC' topic and a labelled issue"
		log "  add that topic on GitHub to opt a repo in; remove it to opt out"
	else
		warn "discovery on with no QUEUE_TOPIC: every repo you own is in scope"
		log "  set QUEUE_TOPIC=pi-agent to opt repos in deliberately"
	fi
else
	log "discovery off: only repos already cloned into $GITHUB_DIR are checked"
	log "  set QUEUE_DISCOVER=1 to have it find and clone the others"
fi
log ""
log "label an issue '${AGENT_LABEL:-agent:queued}' and it will be picked up."
log "  systemctl list-timers pi5-queue.timer     when it next runs"
log "  journalctl -u pi5-queue -f                watch it work"
log "  systemctl start pi5-queue                 run one cycle now"
log "  make queue-timer ARGS=off                 stop it"
summary "queue-timer"
