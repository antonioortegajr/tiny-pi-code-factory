#!/usr/bin/env bash
# File mutation helpers. Every one is idempotent and DRY_RUN aware.

# Snapshot a file before we touch it, once per run, preserving its path.
backup_file() {
	local path="$1" dest
	[ -e "$path" ] || return 0
	dest="$BACKUP_DIR/${path#/}"
	[ -e "$dest" ] && return 0
	[ "$DRY_RUN" = "1" ] && return 0
	mkdir -p "$(dirname "$dest")"
	if [ -r "$path" ]; then cp -a "$path" "$dest" 2>/dev/null || sudo cp -a "$path" "$dest"
	else sudo cp -a "$path" "$dest"; fi
}

# Create a directory, owned by the target user when it lives in their home.
ensure_dir() {
	local dir="$1" sudo_prefix
	[ -d "$dir" ] && return 0
	if [ "$DRY_RUN" = "1" ]; then dry "mkdir -p $dir"; return 0; fi
	sudo_prefix="$(priv_for "$dir")"
	$sudo_prefix mkdir -p "$dir"
	case "$dir" in "$TARGET_HOME"/*) $sudo_prefix chown "$TARGET_USER" "$dir" ;; esac
}

# write_file <path> [mode] - content on stdin. No-op when content already matches.
write_file() {
	local path="$1" mode="${2:-0644}" tmp sudo_prefix
	tmp="$(mktemp)"
	cat > "$tmp"
	if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
		rm -f "$tmp"; skip "$path"; return 0
	fi
	if [ "$DRY_RUN" = "1" ]; then
		dry "write $path"; rm -f "$tmp"; return 0
	fi
	ensure_dir "$(dirname "$path")"
	backup_file "$path"
	sudo_prefix="$(priv_for "$path")"
	$sudo_prefix cp "$tmp" "$path"
	$sudo_prefix chmod "$mode" "$path"
	case "$path" in "$TARGET_HOME"/*) $sudo_prefix chown "$TARGET_USER" "$path" ;; esac
	rm -f "$tmp"
	changed "$path"
}

# install_config <relative path under config/> <destination> [mode]
install_config() {
	local src="$CONFIG_DIR/$1" dest="$2" mode="${3:-0644}"
	[ -f "$src" ] || die "missing tracked config: $src"
	write_file "$dest" "$mode" < "$src"
}

# ini_set <file> <section> <key> <value>
# Section "" targets keys above the first [header]. Preserves comments and
# unrelated keys, which matters for files we share with the desktop's own tools.
ini_set() {
	local file="$1" section="$2" key="$3" value="$4" tmp out
	tmp="$(mktemp)"
	[ -f "$file" ] && { cat "$file" > "$tmp" 2>/dev/null || sudo cat "$file" > "$tmp"; }
	out="$(mktemp)"
	awk -v sec="$section" -v key="$key" -v val="$value" '
		{ lines[NR] = $0 }
		END {
			n = NR; cur = ""; seen = (sec == "" ? 1 : 0)
			target_last = 0; replaced = 0; inserted = 0
			for (i = 1; i <= n; i++) {
				l = lines[i]
				if (l ~ /^[ \t]*\[[^]]*\][ \t]*$/) {
					name = l
					sub(/^[ \t]*\[/, "", name); sub(/\][ \t]*$/, "", name)
					cur = name
					if (cur == sec) { seen = 1; target_last = i }
					continue
				}
				if (cur == sec && seen) {
					if (l ~ ("^[ \t]*" key "[ \t]*=")) {
						if (replaced) { lines[i] = "\001" }
						else { lines[i] = key "=" val; replaced = 1 }
					}
					if (l ~ /[^ \t]/) target_last = i
				}
			}
			for (i = 1; i <= n; i++) {
				if (!replaced && seen && !inserted && i == target_last + 1) {
					print key "=" val; inserted = 1
				}
				if (lines[i] != "\001") print lines[i]
			}
			if (!replaced && seen && !inserted) { print key "=" val }
			if (!seen) {
				if (n > 0) print ""
				print "[" sec "]"
				print key "=" val
			}
		}
	' "$tmp" > "$out"
	write_file "$file" < "$out"
	rm -f "$tmp" "$out"
}

# ensure_line <file> <line> [match-regex]
# Adds the line if no line matches the regex; rewrites it if one does but differs.
ensure_line() {
	local file="$1" line="$2" regex="${3:-}" tmp out
	[ -n "$regex" ] || regex="^$(printf '%s' "$line" | sed 's/[][\.*^$/]/\\&/g')\$"
	tmp="$(mktemp)"
	[ -f "$file" ] && { cat "$file" > "$tmp" 2>/dev/null || sudo cat "$file" > "$tmp"; }
	out="$(mktemp)"
	awk -v re="$regex" -v line="$line" '
		{ if ($0 ~ re) { if (!done) { print line; done = 1 } } else print $0 }
		END { if (!done) print line }
	' "$tmp" > "$out"
	write_file "$file" < "$out"
	rm -f "$tmp" "$out"
}

# json_merge <file> <json object of keys to set>
# Used for editor settings files we must not clobber.
json_merge() {
	local file="$1" patch="$2" out
	has_cmd python3 || { warn "python3 missing, skipping JSON merge for $file"; return 0; }
	out="$(mktemp)"
	if ! python3 - "$file" "$patch" > "$out" <<'PY'
import json, sys, os, re
path, patch = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    raw = open(path, encoding="utf-8").read()
    # VS Code settings allow // comments and trailing commas; tolerate both.
    raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
    raw = re.sub(r',(\s*[}\]])', r'\1', raw)
    try:
        data = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError as e:
        sys.exit(f"could not parse {path}: {e}")
data.update(json.loads(patch))
print(json.dumps(data, indent=2, sort_keys=True))
PY
	then
		warn "leaving $file untouched"; rm -f "$out"; return 0
	fi
	write_file "$file" < "$out"
	rm -f "$out"
}
