#!/usr/bin/env bash
# Hermes Agent - Nous Research's open-source agent harness.
#
# A fuller agent than bin/pi5-agent: terminal commands, file editing, process
# management, web search and browser control, driven by whichever local model
# you are already running. The two are not the same trade:
#
#   pi5-agent      narrow. Issues and a checkout, writes only on an agent/
#                  branch, never merges or closes. Predictable on a small model.
#   hermes-agent   broad, including a terminal tool. More capable, and more to
#                  go wrong when a 2-3B model is the one choosing.
#
# EXPECT THIS NOT TO WORK WELL ON AN 8 GB PI. Nous state that "every recommended
# model gets at least a 64K context window", and they size against GPU memory -
# "a GPU with 8 GB+ runs the small catalog models comfortably". The Pi has no GPU
# and must hold everything in system RAM, so the KV cache alone rules it out:
#
#   model               weights   KV @ 8K   KV @ 64K   total @ 64K
#   qwen3.5:4b-q4_K_M     2.5 GB    1.1 GB     9.0 GB      11.5 GB
#   hermes3:3b            2.0 GB    0.9 GB     7.0 GB       9.0 GB
#   gemma-4-E2B           3.0 GB    0.9 GB     7.5 GB      10.5 GB
#
# (fp16 KV cache, approximate layer/head counts, before the OS.) Every row
# exceeds 8 GB at the context Hermes expects. It is installed here because it is
# worth having on a bigger machine, not because it will shine on this one.
# bin/pi5-agent and opencode are the ones sized for this hardware.
APP_DESCRIPTION="Nous Research agent harness"

app_install() {
	need_sudo

	# The installer fetches Node as a .tar.xz, so xz-utils is not optional.
	apt_install_optional git curl xz-utils

	local hermes_bin=""
	for candidate in "$TARGET_HOME/.local/bin/hermes" "$TARGET_HOME/.hermes/bin/hermes"; do
		[ -x "$candidate" ] && hermes_bin="$candidate" && break
	done
	has_cmd hermes && hermes_bin="$(command -v hermes)"

	if [ -n "$hermes_bin" ]; then
		skip "hermes already installed at $hermes_bin"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "install Hermes Agent from hermes-agent.nousresearch.com/install.sh"
	else
		# It pulls its own Python 3.11, Node 22, ripgrep and ffmpeg - upwards of a
		# gigabyte, and it lands on the boot drive.
		local free_gb
		free_gb="$(df -BG --output=avail "$TARGET_HOME" 2>/dev/null | tail -n1 | tr -dc '0-9')"
		if [ -n "$free_gb" ] && [ "$free_gb" -lt 4 ] 2>/dev/null; then
			warn "only ${free_gb} GB free on the boot drive"
			log "the installer brings its own Node, Python and ffmpeg; free some space first"
			return 1
		fi

		log "installing Hermes Agent (brings Node 22, Python 3.11, ripgrep, ffmpeg)"
		as_user sh -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash' || {
			warn "the installer failed"
			log "alternative:  uv tool install hermes-agent    (or pip install -U hermes-agent)"
			log "docs: https://hermes-agent.nousresearch.com/docs/getting-started/installation"
			return 1
		}
		changed "installed Hermes Agent"
	fi

	# --- pointing it at the local model --------------------------------------
	# Deliberately not writing a config file here: Hermes' own config format is
	# the thing most likely to change between releases, and a stale generated
	# config is worse than none. Print exactly what to set instead.
	local endpoint="" backend=""
	if systemctl is-active --quiet ollama 2>/dev/null; then
		backend="Ollama"; endpoint="http://127.0.0.1:11434/v1"
	elif systemctl is-active --quiet lmstudio-server 2>/dev/null; then
		backend="LM Studio"; endpoint="http://127.0.0.1:${LMS_PORT:-1234}/v1"
	fi

	log ""
	if [ -n "$backend" ]; then
		log "$backend is running at $endpoint. Configure Hermes to use it:"
		log "  hermes setup               # guided first-run configuration"
		log "  hermes model               # choose the model/endpoint"
		log "docs: https://hermes-agent.nousresearch.com/docs/user-guide/local-models"
	else
		warn "no local model server is running"
		log "start one first:  make llm LLM_APP=ollama"
		log "then:  hermes setup"
	fi

	log ""
	log "Note: Hermes has a terminal tool, so it can run commands on this Pi."
	log "bin/pi5-agent is the constrained alternative if you want branch-only writes."

	local ram_gb
	ram_gb="$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
	if [ "$ram_gb" != "0" ] && [ "$ram_gb" -lt 16 ] 2>/dev/null; then
		warn "this machine has ${ram_gb} GB; Hermes expects a 64K context window"
		log "the KV cache alone at 64K is 7-9 GB for a 3-4B model, before the OS"
		log "expect it to struggle here. On this hardware use:  pi5-agent, opencode"
	fi
}
