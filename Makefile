# tiny-pi-code-factory - run these on the Pi itself.
#
#   make all          full setup on a freshly flashed image

#   DRY_RUN=1 make …  print every change without making it

SHELL := /bin/bash
S     := ./scripts
ARGS  ?=

.PHONY: all base storage ssd-state dev harden preflight apps app network mirror llm llm-test doctor queue labels queue-timer \
        capture restore-packages check help

help:
	@sed -n 's/^## //p' $(MAKEFILE_LIST)

## all              preflight, network, base, storage, ssd-state, dark, dev, harden, apps
# apps run last: they are the slowest, and open-webui needs to punch its port
# through the firewall that 'harden' just turned on.
all: preflight network base storage ssd-state dev harden apps
	@echo
	@echo "Done."

## preflight        detect hardware/OS and write state/detected.env
preflight:
	@$(S)/00-preflight.sh

## llm              fast path to a working local model, skipping the apt upgrade
# The model server cannot genuinely go first: it needs the network, curl, and the SSD
# mounted, or a multi-gigabyte model lands on the USB boot drive. This is the
# shortest honest route - everything it depends on, and nothing else.
llm: preflight
	@$(S)/05-network.sh
	@SKIP_UPGRADE=1 $(S)/10-base.sh
	@$(S)/20-storage.sh
	@$(S)/25-ssd-state.sh
	@LLM_FAST=1 $(S)/60-apps.sh ollama
	@echo
	@echo "Server is up. Next:  lms get --help   then   lms load <model>"
	@echo "Finish the rest whenever:  make all"

## labels           create the agent:queued / agent:done / agent:failed labels
labels:
	@$(S)/97-labels.sh $(ARGS)

## queue            work every GitHub issue labelled agent:queued, opening draft PRs
# Read-only without ARGS. Pass ARGS=--allow-write to actually do the work.
queue:
	@bin/pi5-agent --queue $(ARGS)

## queue-timer      poll GitHub for labelled issues on a timer (ARGS=off to stop)
queue-timer: preflight
	@$(S)/98-queue-timer.sh $(ARGS)

## doctor           check the whole chain and say what to fix
doctor: preflight
	@$(S)/95-doctor.sh

## llm-test         prove the local AI works: inference, speed, tool calling
llm-test:
	@bin/pi5-agent --selftest

## network          verify the Pi can reach github.com, join Wi-Fi if configured
network: preflight
	@$(S)/05-network.sh

## base             updates, hostname, timezone, locale, core packages
base: preflight
	@$(S)/10-base.sh

## storage          boot order check, HAT SSD mount, zram, trim
storage: preflight
	@$(S)/20-storage.sh $(ARGS)

## ssd-state        keep docker/model/project data on the SSD, not the boot drive
ssd-state: preflight
	@$(S)/25-ssd-state.sh $(ARGS)


## dev              git identity, SSH key, optional uv/node/docker
dev: preflight
	@$(S)/40-dev.sh

## harden           key-only SSH, ufw, unattended-upgrades
harden: preflight
	@$(S)/50-harden.sh

## apps             install everything listed in $$APPS (ollama, open-webui, …)
apps: preflight
	@$(S)/60-apps.sh

## app APP=name     install one app, e.g. make app APP=ollama
app: preflight
	@test -n "$(APP)" || { echo "usage: make app APP=<name>"; exit 1; }
	@$(S)/60-apps.sh "$(APP)"

## capture          record this Pi's packages and config into captured/
capture: preflight
	@$(S)/90-capture.sh



## restore-packages reinstall the packages recorded by 'make capture'
restore-packages: preflight
	@$(S)/92-restore-packages.sh

## mirror           copy this repo onto the SSD so the next reflash has it locally
mirror: preflight
	@$(S)/93-mirror-repo.sh

## check            syntax check and shellcheck every script (runs anywhere)
check:
	@set -e; for f in $(S)/*.sh lib/*.sh apps/*.sh bootstrap.sh; do bash -n "$$f"; done; \
	echo "bash -n: ok"; \
	if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -S warning $(S)/*.sh lib/*.sh apps/*.sh bootstrap.sh && echo "shellcheck: ok"; \
	else \
		echo "shellcheck: not installed, skipped"; \
	fi
