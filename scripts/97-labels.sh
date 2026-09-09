#!/usr/bin/env bash
# Create the queue's labels in a repository. Safe to rerun - existing labels are
# updated rather than duplicated.
#
#   make labels                    # in the current checkout
#   make labels ARGS=owner/name    # somewhere else
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

has_cmd gh || die "gh is not installed (make app APP=gh)"

repo_args=()
[ -n "${1:-}" ] && repo_args=(--repo "$1")

step "Labels${1:+ in $1}"

# name|colour|description
labels="
${AGENT_LABEL:-agent:queued}|1d76db|Queued for the local agent to attempt
${AGENT_LABEL_DONE:-agent:done}|0e8a16|Agent opened a draft PR - awaiting review
${AGENT_LABEL_FAILED:-agent:failed}|b60205|Agent could not complete it - no PR opened
${AGENT_LABEL_OPENCODE:-agent:opencode}|5319e7|Hand this one to opencode instead of the built-in agent
"

printf '%s\n' "$labels" | while IFS='|' read -r name colour desc; do
	[ -n "$name" ] || continue
	if [ "$DRY_RUN" = "1" ]; then
		dry "create label '$name'"
		continue
	fi
	# --force updates an existing label instead of failing on it.
	if as_user gh label create "$name" --color "$colour" --description "$desc" \
		--force "${repo_args[@]}" >/dev/null 2>&1; then
		changed "label '$name'"
	else
		warn "could not create '$name' - is gh authenticated for this repo?"
	fi
done

log ""
log "Tag an issue '${AGENT_LABEL:-agent:queued}', then:  make queue ARGS=--allow-write"
log "Add '${AGENT_LABEL_OPENCODE:-agent:opencode}' as well to route it through opencode."
summary "labels"
