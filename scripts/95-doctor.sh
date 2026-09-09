#!/usr/bin/env bash
# Check the whole chain and say what to do about anything broken.
#
# Ordered by dependency, so the first FAIL is usually the real problem and
# everything below it is a consequence.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

PASS=0
FAIL=0
NOTE=0

ok()    { PASS=$((PASS + 1)); printf '  %sok%s    %s\n' "$C_GRN" "$C_RESET" "$*"; }
bad()   { FAIL=$((FAIL + 1)); printf '  %sFAIL%s  %s\n' "$C_RED" "$C_RESET" "$*"; }
note()  { NOTE=$((NOTE + 1)); printf '  %s--%s    %s\n' "$C_DIM" "$C_RESET" "$*"; }
fix()   { printf '        %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

step "System"
log "$OS_PRETTY on $MODEL"
log "compositor: $COMPOSITOR    desktop: $([ "${HAS_DESKTOP:-0}" = 1 ] && echo yes || echo 'no (Lite)')"

ram_total="$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
ram_avail="$(awk '/MemAvailable/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
log "RAM: ${ram_avail} GB available of ${ram_total} GB"
# A model has to fit in what is free, not in what is installed.
awk -v a="$ram_avail" 'BEGIN { exit !(a < 2.5) }' && \
	note "under 2.5 GB free - even a 2 GB model will struggle" && \
	fix "close things, or use Lite: the desktop costs 0.5-1 GB"

step "Storage"
if [ -z "${SSD_MOUNT_POINT:-}" ]; then
	note "SSD_MOUNT_POINT is unset, SSD support disabled"
elif mountpoint -q "$SSD_MOUNT_POINT" 2>/dev/null; then
	free_gb="$(df -BG --output=avail "$SSD_MOUNT_POINT" 2>/dev/null | tail -n1 | tr -dc '0-9')"
	ok "$SSD_MOUNT_POINT mounted, ${free_gb:-?} GB free"
	for d in "$SSD_MOUNT_POINT/GitHub" "$SSD_MOUNT_POINT/docker"; do
		[ -d "$d" ] && ok "$d exists" || note "$d missing (run: make ssd-state)"
	done
	mountpoint -q "$TARGET_HOME/.ssh" 2>/dev/null \
		&& ok "~/.ssh is on the SSD - keys survive a reflash" \
		|| note "~/.ssh is on the boot drive (run: make ssd-state)"
else
	bad "$SSD_MOUNT_POINT is not mounted"
	fix "make storage      # then: make ssd-state"
fi

boot_free="$(df -BG --output=avail / 2>/dev/null | tail -n1 | tr -dc '0-9')"
[ -n "$boot_free" ] && [ "$boot_free" -lt 3 ] 2>/dev/null \
	&& note "only ${boot_free} GB free on the boot drive" \
	|| true

step "Model server"

BACKEND=""
ENDPOINT=""
INSTALLED=""
if systemctl is-active --quiet lmstudio-server 2>/dev/null; then
	ok "lmstudio-server is running"
	BACKEND="lmstudio"; ENDPOINT="http://127.0.0.1:${LMS_PORT:-1234}/v1"
elif [ -x "$TARGET_HOME/.lmstudio/bin/lms" ]; then
	INSTALLED="lmstudio"
	bad "LM Studio is installed but lmstudio-server is not running"
	fix "journalctl -u lmstudio-server -n 30 --no-pager"
	fix "if it will not start, switch backend:  make llm LLM_APP=ollama"
fi

if systemctl is-active --quiet ollama 2>/dev/null; then
	ok "ollama is running"
	[ -z "$BACKEND" ] && { BACKEND="ollama"; ENDPOINT="http://127.0.0.1:11434/v1"; }
elif has_cmd ollama; then
	INSTALLED="${INSTALLED:+$INSTALLED }ollama"
	bad "ollama is installed but not running"
	fix "sudo systemctl status ollama"
fi

if [ -z "$BACKEND" ] && [ -z "$INSTALLED" ]; then
	bad "no model server installed"
	fix "make llm                    # LM Studio"
	fix "make llm LLM_APP=ollama     # Ollama, fewer moving parts on Lite"
elif [ -z "$BACKEND" ]; then
	# Installed but dead is a different problem from absent, and saying
	# "not installed" underneath "is installed" just reads as a broken check.
	log "installed but not running: $INSTALLED"
fi

step "Model"

if [ -n "$ENDPOINT" ]; then
	models="$( { curl -fsS --max-time 10 "$ENDPOINT/models" 2>/dev/null || true; } \
		| tr ',' '\n' | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' )"
	if [ -n "$models" ]; then
		ok "endpoint answering at $ENDPOINT"
		printf '        %s\n' $models
	else
		bad "no model loaded at $ENDPOINT"
		case "$BACKEND" in
			lmstudio) fix "lms ls    then    lms load <model> --context-length ${LMS_CONTEXT:-8192}" ;;
			ollama)   fix "ollama pull ${OLLAMA_MODEL:-hermes3:3b}" ;;
		esac
	fi
fi

step "Tool calling"
# The thing most likely to be broken, and the thing the agent depends on.
if [ -z "$ENDPOINT" ] || [ -z "${models:-}" ]; then
	note "skipped - no loaded model to ask"
elif [ ! -x "$REPO_ROOT/bin/pi5-agent" ]; then
	note "bin/pi5-agent missing"
else
	if AGENT_BASE_URL="$ENDPOINT" "$REPO_ROOT/bin/pi5-agent" --selftest >/dev/null 2>&1; then
		ok "inference and tool calling both work - see 'make llm-test' for detail"
	else
		bad "the local AI check did not pass"
		fix "make llm-test          # staged output: endpoint, model, inference, tools"
		if [ "$BACKEND" != "ollama" ]; then
			fix "known-good fallback:  make app APP=ollama && pi5-agent --backend ollama --selftest"
			fix "Hermes 3 is trained for tool use and Ollama has parsed its format for years."
		fi
	fi
fi

step "Context budget"
# Agents differ enormously in how much context they assume. Saying so here beats
# discovering it when one silently truncates its own instructions.
ctx="${LMS_CONTEXT:-8192}"
log "configured context: $ctx tokens"
log "pi5-agent and opencode are sized for this; both keep a short tool menu"
if [ -n "$ram_total" ]; then
	awk -v r="$ram_total" 'BEGIN { exit !(r < 16) }' && 		note "hermes-agent expects 64K; at ${ram_total} GB the KV cache alone would not fit" && 		fix "use pi5-agent or opencode on this machine"
fi

step "GitHub"
if has_cmd gh; then
	if as_user gh auth status >/dev/null 2>&1; then
		ok "gh is authenticated"
	else
		bad "gh is not authenticated"
		fix "gh auth login"
	fi
else
	bad "gh is not installed"
	fix "make app APP=gh"
fi

remote="$(as_user git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
case "$remote" in
	*@github.com/*|*://*:*@*)
		bad "a credential is embedded in the git remote URL"
		fix "git remote set-url origin https://github.com/antonioortegajr/my-pi5-setup.git"
		fix "or better, switch to ssh: git@github.com:antonioortegajr/my-pi5-setup.git"
		;;
	git@*) ok "git remote uses ssh - no token needed" ;;
	*) [ -n "$remote" ] && ok "git remote is clean" ;;
esac

step "Web UI"
if has_cmd docker; then
	if sudo -n docker ps --format '{{.Names}}' 2>/dev/null | grep -qx open-webui; then
		ok "open-webui is running on port ${OPEN_WEBUI_PORT:-8080}"
	elif sudo -n docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx open-webui; then
		bad "the open-webui container exists but is stopped"
		fix "docker start open-webui"
	else
		note "open-webui not installed (make app APP=open-webui)"
	fi
else
	note "docker not installed"
fi

if has_cmd ufw && sudo -n ufw status 2>/dev/null | grep -q '^Status: active'; then
	sudo -n ufw status 2>/dev/null | grep -q "^${OPEN_WEBUI_PORT:-8080}/tcp" \
		&& ok "ufw allows ${OPEN_WEBUI_PORT:-8080}/tcp" \
		|| note "ufw is on and ${OPEN_WEBUI_PORT:-8080}/tcp is closed - the UI is Pi-only"
fi

printf '\n%s%d ok, %d failed, %d notes%s\n' "$C_BOLD" "$PASS" "$FAIL" "$NOTE" "$C_RESET"
[ "$FAIL" -gt 0 ] && printf '%sFix the first FAIL first - the rest are often consequences of it.%s\n' \
	"$C_DIM" "$C_RESET"
exit 0
