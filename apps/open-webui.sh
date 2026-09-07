#!/usr/bin/env bash
# Open WebUI - browser front end for whichever local model server is installed.
#
# Runs with --network=host so the container reaches the model server on
# 127.0.0.1 without that server having to listen on the LAN itself.
APP_DESCRIPTION="browser UI for the local model server"

OPEN_WEBUI_IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-8080}"

app_install() {
	need_sudo
	ensure_docker

	# Point at whichever model server is actually installed.
	local backend_env=()
	if [ -x "$TARGET_HOME/.lmstudio/bin/lms" ]; then
		backend_env+=(-e "OPENAI_API_BASE_URL=http://127.0.0.1:${LMS_PORT:-1234}/v1"
		              -e "OPENAI_API_KEY=lm-studio")
		log "backend: LM Studio on port ${LMS_PORT:-1234}"
	fi
	if has_cmd ollama; then
		backend_env+=(-e "OLLAMA_BASE_URL=http://127.0.0.1:11434")
		log "backend: Ollama on port 11434"
	fi
	if [ ${#backend_env[@]} -eq 0 ]; then
		warn "no model server installed; add lm-studio or ollama to APPS"
	fi

	# Group membership only takes effect on the next login, so right after
	# ensure_docker added the user this run still has to go through sudo.
	local d="sudo docker"
	if [ "$(id -un)" = "$TARGET_USER" ] \
		&& id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
		d="docker"
	fi

	if [ "$DRY_RUN" = "1" ]; then
		dry "docker run open-webui on port $OPEN_WEBUI_PORT"
		return 0
	fi

	if $d ps -a --format '{{.Names}}' 2>/dev/null | grep -qx open-webui; then
		skip "open-webui container already exists"
		$d start open-webui >/dev/null 2>&1 || true
	else
		log "pulling $OPEN_WEBUI_IMAGE (large image, several minutes on a Pi)"
		$d pull "$OPEN_WEBUI_IMAGE" || return 1
		# Named volume keeps chats and accounts across container upgrades.
		$d run -d \
			--name open-webui \
			--network=host \
			--restart always \
			-e "PORT=$OPEN_WEBUI_PORT" \
			"${backend_env[@]}" \
			-v open-webui:/app/backend/data \
			"$OPEN_WEBUI_IMAGE" >/dev/null || return 1
		changed "started open-webui"
	fi

	# 50-harden turns ufw on with only SSH allowed, which would leave the UI
	# unreachable from the Mac. Open its port explicitly.
	if has_cmd ufw && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
		if sudo ufw status 2>/dev/null | grep -q "^$OPEN_WEBUI_PORT/tcp"; then
			skip "ufw already allows $OPEN_WEBUI_PORT/tcp"
		else
			sudo ufw allow "$OPEN_WEBUI_PORT/tcp" >/dev/null && changed "ufw allows $OPEN_WEBUI_PORT/tcp"
		fi
	fi

	log "open it at:  http://${PI_HOSTNAME:-$(hostname)}.local:$OPEN_WEBUI_PORT"
	log "the first account you create there becomes the admin"
	log "note: --network=host means this is reachable from your LAN"
}
