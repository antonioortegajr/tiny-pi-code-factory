#!/usr/bin/env bash
# Ollama - the local model runner.
#
# Worth choosing when tool calling matters. Ollama's parser for the Hermes
# <tool_call> format is long established, where support for a newer model's
# format can lag behind the model's release - which is the failure mode
# pi5-agent is most likely to hit. hermes3:3b is the default here for that
# reason: trained for function calling, and 2 GB.
#
# Models are large, so they go on the SSD rather than the USB boot drive.
APP_DESCRIPTION="local LLM runner (Ollama)"

app_install() {
	need_sudo

	# --- install -------------------------------------------------------------
	if has_cmd ollama; then
		skip "ollama already installed"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install ollama from ollama.com/install.sh"
	else
		log "installing ollama (arm64, brings its own systemd service)"
		curl -fsSL https://ollama.com/install.sh | sh || return 1
		changed "installed ollama"
	fi

	# --- models on the SSD ---------------------------------------------------
	local models_dir=""
	if [ -n "${OLLAMA_MODELS_DIR:-}" ]; then
		models_dir="$OLLAMA_MODELS_DIR"
	elif [ -n "${SSD_MOUNT_POINT:-}" ] && mountpoint -q "$SSD_MOUNT_POINT" 2>/dev/null; then
		models_dir="$SSD_MOUNT_POINT/ollama"
	fi

	if [ -n "$models_dir" ]; then
		log "model storage: $models_dir"
		ensure_dir "$models_dir"
		# The service runs as the ollama user, not as you.
		[ "$DRY_RUN" = "1" ] || sudo chown -R ollama:ollama "$models_dir" 2>/dev/null || true
	else
		warn "SSD not mounted at ${SSD_MOUNT_POINT:-unset}; models will land on the boot drive"
		log "run 'make storage' first, or set OLLAMA_MODELS_DIR in settings.local.env"
	fi

	# --- service configuration -----------------------------------------------
	# A drop-in, so an ollama upgrade cannot overwrite it.
	{
		printf '# Managed by my-pi5-setup (apps/ollama.sh)\n[Service]\n'
		[ -n "$models_dir" ] && printf 'Environment="OLLAMA_MODELS=%s"\n' "$models_dir"
		# Localhost only by default. Open WebUI reaches it via --network=host,
		# so there is no reason to expose this to the LAN.
		printf 'Environment="OLLAMA_HOST=%s"\n' "${OLLAMA_HOST:-127.0.0.1:11434}"
		# Ollama's own default is 4096 tokens regardless of what the model
		# supports - qwen3.5:4b handles 262144 - and it is a server setting, not
		# something a request to the OpenAI-compatible endpoint can change. The
		# ceiling here is RAM, not the model: the fp16 KV cache costs roughly
		# 140 KB per token, so 8K is ~1.1 GB on top of 2.5 GB of weights and 32K
		# would not leave room for the OS.
		printf 'Environment="OLLAMA_CONTEXT_LENGTH=%s"\n' "${OLLAMA_CONTEXT_LENGTH:-8192}"
		printf 'Environment="OLLAMA_KEEP_ALIVE=%s"\n' "${OLLAMA_KEEP_ALIVE:--1}"
		# Flash attention is what makes a quantized KV cache possible; q8_0
		# roughly halves its memory, which is what buys a 16K window on 8 GB.
		printf 'Environment="OLLAMA_FLASH_ATTENTION=%s"\n' "${OLLAMA_FLASH_ATTENTION:-1}"
		printf 'Environment="OLLAMA_KV_CACHE_TYPE=%s"\n' "${OLLAMA_KV_CACHE_TYPE:-q8_0}"
	} | write_file /etc/systemd/system/ollama.service.d/10-my-pi5-setup.conf

	if [ "$DRY_RUN" != "1" ]; then
		sudo systemctl daemon-reload
		sudo systemctl enable ollama >/dev/null 2>&1
		sudo systemctl restart ollama >/dev/null 2>&1 \
			|| warn "could not start the ollama service"
	fi

	# --- models --------------------------------------------------------------
	# 'make llm LLM_APP=ollama' sets LLM_FAST=1, meaning "pull the default now".
	local to_pull="${OLLAMA_PULL:-}"
	if [ -z "$to_pull" ] && [ "${LLM_FAST:-0}" = "1" ]; then
		to_pull="${OLLAMA_MODEL:-qwen3.5:4b-q4_K_M}"
	fi

	if [ -n "$to_pull" ]; then
		local ram_gb
		ram_gb="$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
		[ "$ram_gb" != "0" ] && log "system RAM: ${ram_gb} GB (the model must fit in this)"

		local m
		for m in $to_pull; do
			if [ "$DRY_RUN" = "1" ]; then
				dry "ollama pull $m"
			elif ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$m"; then
				skip "model $m already pulled"
			else
				log "pulling $m (gigabytes; several minutes on a Pi)"
				if ollama pull "$m"; then
					changed "pulled $m"
					log "try it:  ollama run $m"
				else
					warn "pull failed: $m"
					log "check the tag at https://ollama.com/library/${m%%:*}"
				fi
			fi
		done
	else
		log "no models pulled. Choices for an 8 GB Pi:"
		log "  ollama pull qwen3.5:4b-q4_K_M   ~2.5 GB, agentic coding - the default"
		log "  ollama pull hermes3:3b          2.0 GB, fallback if tool calls misbehave"
		log "  ollama pull hermes3:8b          4.7 GB, fits but slow (~2-3 tok/s)"
		log "set OLLAMA_MODEL or OLLAMA_PULL in settings.local.env to automate it"
	fi

	log "OpenAI-compatible endpoint:  http://127.0.0.1:11434/v1"
	log "point the agent at it:  AGENT_BASE_URL=http://127.0.0.1:11434/v1 pi5-agent --selftest"
}
