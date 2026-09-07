#!/usr/bin/env bash
# opencode - terminal coding agent, pointed at the local model server.
#
# Note on naming: the `opencode-pi` package on pi.dev is a different thing. Its
# "Pi" is the Pi Coding Agent, not a Raspberry Pi, and it bridges OpenCode's
# free *hosted* models into that agent. This installs plain opencode and
# configures it against the model already running on this machine, so nothing
# leaves the Pi.
APP_DESCRIPTION="terminal coding agent on the local model"

app_install() {
	# --- install -------------------------------------------------------------
	if has_cmd opencode || [ -x "$TARGET_HOME/.opencode/bin/opencode" ]; then
		skip "opencode already installed"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install opencode"
	else
		log "installing opencode"
		if as_user sh -c 'curl -fsSL https://opencode.ai/install | bash'; then
			changed "installed opencode"
		elif has_cmd npm; then
			log "install script failed, trying npm"
			as_user npm install -g opencode-ai && changed "installed opencode via npm" || {
				warn "could not install opencode"
				return 1
			}
		else
			warn "could not install opencode, and npm is not available for the fallback"
			log "set INSTALL_NODE=1 in settings.local.env and rerun 'make dev' to get npm"
			return 1
		fi
	fi

	ensure_line "$TARGET_HOME/.bashrc" \
		'case ":$PATH:" in *":$HOME/.opencode/bin:"*) ;; *) PATH="$HOME/.opencode/bin:$PATH" ;; esac' \
		'HOME/\.opencode/bin'

	# --- point it at whichever backend is running ----------------------------
	local provider="" base_url="" pretty=""
	if systemctl is-active --quiet ollama 2>/dev/null; then
		provider="ollama"; base_url="http://127.0.0.1:11434/v1"; pretty="Ollama (local)"
	elif systemctl is-active --quiet lmstudio-server 2>/dev/null; then
		provider="lmstudio"; base_url="http://127.0.0.1:${LMS_PORT:-1234}/v1"; pretty="LM Studio (local)"
	fi

	if [ -z "$provider" ]; then
		warn "no local model server running; leaving opencode unconfigured"
		log "start one first:  make llm LLM_APP=ollama    then rerun this"
		return 0
	fi

	# Ask the server what it actually has loaded rather than guessing a model id -
	# opencode needs the id to match exactly.
	local model_id=""
	if [ "$DRY_RUN" != "1" ]; then
		model_id="$( { curl -fsS --max-time 10 "$base_url/models" 2>/dev/null || true; } \
			| tr ',' '\n' \
			| sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 )"
	fi
	if [ -z "$model_id" ]; then
		warn "no model loaded at $base_url - writing the config without a model entry"
		log "load one, then rerun:  make app APP=opencode"
	else
		log "using model: $model_id"
	fi

	# json_merge replaces the provider key wholesale but leaves the rest of the
	# file alone, so hand-added opencode settings survive a rerun.
	local cfg="$TARGET_HOME/.config/opencode/opencode.json"
	ensure_dir "$(dirname "$cfg")"
	if [ "$DRY_RUN" = "1" ]; then
		dry "configure $cfg for $pretty at $base_url"
	else
		local models_json="{}"
		[ -n "$model_id" ] && models_json="{\"$model_id\": {\"name\": \"$model_id (local)\"}}"
		json_merge "$cfg" "{
			\"\$schema\": \"https://opencode.ai/config.json\",
			\"provider\": {
				\"$provider\": {
					\"npm\": \"@ai-sdk/openai-compatible\",
					\"name\": \"$pretty\",
					\"options\": {\"baseURL\": \"$base_url\"},
					\"models\": $models_json
				}
			}
		}"
	fi

	log ""
	log "run it in a checkout:  cd ~/GitHub/<repo> && opencode"
	log "pick the model with /models if it does not default to the local one"
}
