#!/usr/bin/env bash
# Single entry point for scripts: source this, get everything.
set -euo pipefail
_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./log.sh
. "$_lib/log.sh"
# shellcheck source=./util.sh
. "$_lib/util.sh"
# shellcheck source=./file.sh
. "$_lib/file.sh"
# shellcheck source=./pkg.sh
. "$_lib/pkg.sh"
unset _lib

# Tracked defaults, then untracked personal overrides. settings.local.env is
# gitignored, so machine-specific values never end up in a commit.
if [ -r "$REPO_ROOT/settings.env" ]; then
	# shellcheck source=../settings.env
	. "$REPO_ROOT/settings.env"
fi
if [ -r "$REPO_ROOT/settings.local.env" ]; then
	# shellcheck disable=SC1091
	. "$REPO_ROOT/settings.local.env"
fi
