#!/usr/bin/env bash
# Install the apps listed in $APPS, one file per app under apps/.
#
#   make apps              everything in $APPS
#   make app APP=lm-studio just one, whether or not it is in $APPS
#
# Each apps/<name>.sh defines app_install(). It is called from an || list, so a
# failing app is reported and the rest still run.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

requested="${1:-${APPS:-}}"

step "Apps"

if [ -z "$requested" ]; then
	log "APPS is empty in settings.env - nothing to install"
	log "available: $(cd "$REPO_ROOT/apps" && ls *.sh 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')"
	summary "apps"; exit 0
fi

failed=""
for app in $requested; do
	file="$REPO_ROOT/apps/$app.sh"
	if [ ! -f "$file" ]; then
		warn "no installer for '$app' (expected $file)"
		failed="$failed $app"
		continue
	fi

	unset -f app_install
	APP_DESCRIPTION=""
	# shellcheck disable=SC1090
	. "$file"

	if ! declare -F app_install >/dev/null; then
		warn "$app.sh does not define app_install()"
		failed="$failed $app"
		continue
	fi

	step "App: $app${APP_DESCRIPTION:+ - $APP_DESCRIPTION}"
	app_install || { warn "$app failed"; failed="$failed $app"; }
done

[ -n "$failed" ] && warn "failed:$failed"

summary "apps"
