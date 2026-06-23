#!/usr/bin/env bash
# Install, update, or remove a nono pack locally for dev / testing.
# Reads <pack>/package.json and applies all wiring without touching the registry.
#
# Usage:
#   scripts/dev-install.sh install  <pack> [--namespace <ns>] [--dry-run]
#   scripts/dev-install.sh update   <pack> [--namespace <ns>] [--dry-run]
#   scripts/dev-install.sh remove   <pack> [--namespace <ns>] [--dry-run]
#
# Supported wiring types:
#   symlink            ln -snf link -> target
#   write_file         cp source dest
#   json_merge         deep-merge patch JSON into file
#   json_array_append  append entries to a dot-path array (dedup by key_field)
#   toml_block         append/replace a marked block in a TOML file
#   yaml_merge         deep-merge patch YAML into file (requires PyYAML)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'USAGE' >&2
Usage: scripts/dev-install.sh <command> <pack> [options]

Commands:
  install   Apply all wiring from <pack>/package.json
  update    Re-apply wiring (idempotent; safe after content changes)
  remove    Undo all wiring from <pack>/package.json

  <pack>    Pack directory under repo root (e.g. claude, codex, copilot-cli)

Options:
  --namespace <ns>   Value for $NS variable (default: nolabs-ai)
  --dry-run          Print actions; make no changes

Profiles:
  Local profile artifacts are installed as <install_as>-dev, e.g.
  `codex` becomes `codex-dev`.
USAGE
  exit 2
}

[[ $# -ge 2 ]] || usage

CMD="$1"
PACK="$2"
shift 2

case "$CMD" in
  install|update|remove) ;;
  *) echo "error: unknown command '$CMD'" >&2; usage ;;
esac

NS="nolabs-ai"
DRY_RUN=0
PROFILE_SUFFIX="-dev"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)   NS="${2:?--namespace requires a value}"; shift ;;
    --namespace=*) NS="${1#*=}" ;;
    --dry-run)     DRY_RUN=1 ;;
    -h|--help)     usage ;;
    *)             echo "error: unknown flag '$1'" >&2; usage ;;
  esac
  shift
done

PACK_DIR="$REPO_ROOT/$PACK"
[[ -d "$PACK_DIR" ]]              || { echo "error: pack directory not found: $PACK_DIR" >&2; exit 1; }
[[ -f "$PACK_DIR/package.json" ]] || { echo "error: missing $PACK/package.json" >&2; exit 1; }

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
NONO_CONFIG="$XDG_CONFIG_HOME/nono"
NONO_PACKAGES="$NONO_CONFIG/packages"
NONO_PROFILES_DIR="$NONO_CONFIG/profiles"

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ── Variable expansion ───────────────────────────────────────────────────────

expand_vars() {
  local s="$1"
  s="${s//\$HOME/$HOME}"
  s="${s//\$XDG_CONFIG_HOME/$XDG_CONFIG_HOME}"
  s="${s//\$NONO_CONFIG/$NONO_CONFIG}"
  s="${s//\$NONO_PACKAGES/$NONO_PACKAGES}"
  s="${s//\$PACK_DIR/$PACK_DIR}"
  s="${s//\$NS/$NS}"
  s="${s//\$NOW/$NOW}"
  printf '%s' "$s"
}

read_and_expand() {
  expand_vars "$(cat "$1")"
}

# ── Logging / dry-run ────────────────────────────────────────────────────────

log()  { printf '  %s\n' "$*"; }
info() { printf '%s\n' "$*"; }

doit() {
  if (( DRY_RUN )); then
    printf '    [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# ── JSON field extraction (python3, always available on macOS/Linux) ─────────

jfield() {
  # jfield <json-string> <key>  →  value as plain string
  python3 -c "import sys,json; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2],''))" "$1" "$2"
}

jfield_expand() {
  expand_vars "$(jfield "$1" "$2")"
}

# ── Python helpers for structured file mutation ──────────────────────────────

py_json_merge() {
  # Deep-merge patch (JSON string) into target_file; creates file if absent.
  local target_file="$1" patch_content="$2"
  python3 - "$target_file" "$patch_content" <<'PYEOF'
import sys, json

target_path  = sys.argv[1]
patch_str    = sys.argv[2]

try:
    with open(target_path) as f:
        target = json.load(f)
except (FileNotFoundError, json.JSONDecodeError, ValueError):
    target = {}

patch = json.loads(patch_str)

def deep_merge(base, overlay):
    result = dict(base)
    for k, v in overlay.items():
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = deep_merge(result[k], v)
        else:
            result[k] = v
    return result

merged = deep_merge(target, patch)
with open(target_path, 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')
PYEOF
}

py_json_merge_remove() {
  # Remove keys present in patch (JSON string) from target_file.
  local target_file="$1" patch_content="$2"
  [[ -f "$target_file" ]] || return 0
  python3 - "$target_file" "$patch_content" <<'PYEOF'
import sys, json

target_path = sys.argv[1]
patch_str   = sys.argv[2]

try:
    with open(target_path) as f:
        target = json.load(f)
except (FileNotFoundError, json.JSONDecodeError, ValueError):
    sys.exit(0)

patch = json.loads(patch_str)

def deep_remove(base, overlay):
    result = dict(base)
    for k, v in overlay.items():
        if k not in result:
            continue
        if isinstance(v, dict) and isinstance(result[k], dict):
            result[k] = deep_remove(result[k], v)
            if not result[k]:
                del result[k]
        else:
            del result[k]
    return result

cleaned = deep_remove(target, patch)
with open(target_path, 'w') as f:
    json.dump(cleaned, f, indent=2)
    f.write('\n')
PYEOF
}

py_json_array_append() {
  # Append entries (JSON string, array or single object) to the array at
  # dot_path in target_file, deduplicating by key_field (dot-notation).
  local target_file="$1" dot_path="$2" entries_content="$3" key_field="$4"
  python3 - "$target_file" "$dot_path" "$entries_content" "$key_field" <<'PYEOF'
import sys, json

target_path   = sys.argv[1]
dot_path      = sys.argv[2]
entries_str   = sys.argv[3]
key_field     = sys.argv[4]

try:
    with open(target_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError, ValueError):
    data = {}

new_entries = json.loads(entries_str)
if not isinstance(new_entries, list):
    new_entries = [new_entries]

path_parts = dot_path.split('.')
key_parts  = key_field.split('.')

def get_nested(obj, parts):
    for p in parts:
        if isinstance(obj, list):
            try:
                p = int(p)
            except ValueError:
                pass
        try:
            obj = obj[p]
        except (KeyError, IndexError, TypeError):
            return None
    return obj

# Navigate or create the array at dot_path
arr = get_nested(data, path_parts)
if not isinstance(arr, list):
    arr = []
    cur = data
    for part in path_parts[:-1]:
        if part not in cur:
            cur[part] = {}
        cur = cur[part]
    cur[path_parts[-1]] = arr

existing_keys = {get_nested(e, key_parts) for e in arr}

for entry in new_entries:
    key_val = get_nested(entry, key_parts)
    if key_val not in existing_keys:
        arr.append(entry)
        existing_keys.add(key_val)

with open(target_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF
}

py_json_array_remove() {
  # Remove entries matching key_field values from the array at dot_path.
  local target_file="$1" dot_path="$2" entries_content="$3" key_field="$4"
  [[ -f "$target_file" ]] || return 0
  python3 - "$target_file" "$dot_path" "$entries_content" "$key_field" <<'PYEOF'
import sys, json

target_path   = sys.argv[1]
dot_path      = sys.argv[2]
entries_str   = sys.argv[3]
key_field     = sys.argv[4]

try:
    with open(target_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError, ValueError):
    sys.exit(0)

remove_entries = json.loads(entries_str)
if not isinstance(remove_entries, list):
    remove_entries = [remove_entries]

path_parts = dot_path.split('.')
key_parts  = key_field.split('.')

def get_nested(obj, parts):
    for p in parts:
        if isinstance(obj, list):
            try:
                p = int(p)
            except ValueError:
                pass
        try:
            obj = obj[p]
        except (KeyError, IndexError, TypeError):
            return None
    return obj

arr = get_nested(data, path_parts)
if not isinstance(arr, list):
    sys.exit(0)

keys_to_remove = {get_nested(e, key_parts) for e in remove_entries}

cur = data
for part in path_parts[:-1]:
    cur = cur[part]
cur[path_parts[-1]] = [e for e in arr if get_nested(e, key_parts) not in keys_to_remove]

with open(target_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF
}

py_local_shell_scripts_via_bash() {
  # Local dev installs may point agent hook commands at scripts in this
  # checkout. A nono profile can allow reading the checkout while denying
  # direct process-exec from it, so wrap local .sh command fields with
  # `/bin/bash <script>` and leave package wiring untouched.
  local entries_content="$1"
  python3 - "$entries_content" "$PACK_DIR" <<'PYEOF'
import json, shlex, sys

entries_str = sys.argv[1]
entries = json.loads(entries_str)
pack_dir = sys.argv[2].rstrip("/")

def rewrite_value(value):
    if isinstance(value, list):
        return [rewrite_value(item) for item in value]
    if isinstance(value, dict):
        rewritten = {}
        for key, item in value.items():
            if key in {"command", "bash"}:
                rewritten[key] = rewrite_command(item)
            else:
                rewritten[key] = rewrite_value(item)
        return rewritten
    return value

def rewrite_command(command):
    if not isinstance(command, str):
        return command
    if command.startswith(("/bin/bash ", "bash ")):
        return command
    if command.startswith(pack_dir + "/") and command.endswith(".sh"):
        return "/bin/bash " + shlex.quote(command)
    return command

rewritten = rewrite_value(entries)
if rewritten == entries:
    print(entries_str)
else:
    print(json.dumps(rewritten))
PYEOF
}

maybe_wrap_local_shell_scripts() {
  local entries_content="$1"
  py_local_shell_scripts_via_bash "$entries_content"
}

py_toml_block_apply() {
  # Remove any existing marked block, then append the new one.
  local target_file="$1" marker_id="$2" block_content="$3" position="${4:-bottom}"
  python3 - "$target_file" "$marker_id" "$block_content" "$position" <<'PYEOF'
import sys

target_path   = sys.argv[1]
marker_id     = sys.argv[2]
block_content = sys.argv[3]
position      = sys.argv[4]

begin_marker = f'# BEGIN nono-pack:{marker_id}'
end_marker   = f'# END nono-pack:{marker_id}'

try:
    with open(target_path) as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

# Strip existing block
out, skip = [], False
for line in lines:
    stripped = line.rstrip()
    if stripped == begin_marker:
        skip = True
        continue
    if skip and stripped == end_marker:
        skip = False
        continue
    if not skip:
        out.append(line)

block = [f'{begin_marker}\n']
for bline in block_content.splitlines():
    block.append(f'{bline}\n')
block.append(f'{end_marker}\n')

if position == "top":
    while out and not out[0].strip():
        out.pop(0)
    out = block + (['\n'] if out else []) + out
else:
    while out and not out[-1].strip():
        out.pop()
    if out:
        out.append('\n')
    out.extend(block)

import os
os.makedirs(os.path.dirname(target_path) or '.', exist_ok=True)
with open(target_path, 'w') as f:
    f.writelines(out)
PYEOF
}

py_toml_block_remove() {
  # Remove the marked block from target_file.
  local target_file="$1" marker_id="$2"
  [[ -f "$target_file" ]] || return 0
  python3 - "$target_file" "$marker_id" <<'PYEOF'
import sys

target_path = sys.argv[1]
marker_id   = sys.argv[2]

begin_marker = f'# BEGIN nono-pack:{marker_id}'
end_marker   = f'# END nono-pack:{marker_id}'

with open(target_path) as f:
    lines = f.readlines()

out, skip = [], False
for line in lines:
    stripped = line.rstrip()
    if stripped == begin_marker:
        skip = True
        continue
    if skip and stripped == end_marker:
        skip = False
        continue
    if not skip:
        out.append(line)

while out and not out[-1].strip():
    out.pop()

with open(target_path, 'w') as f:
    f.writelines(out)
PYEOF
}

py_yaml_merge() {
  local target_file="$1" patch_content="$2"
  python3 - "$target_file" "$patch_content" <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    print("warning: PyYAML not installed; skipping yaml_merge", file=sys.stderr)
    sys.exit(0)

target_path = sys.argv[1]
patch_str   = sys.argv[2]

try:
    with open(target_path) as f:
        target = yaml.safe_load(f) or {}
except FileNotFoundError:
    target = {}

patch = yaml.safe_load(patch_str) or {}

def deep_merge(base, overlay):
    result = dict(base)
    for k, v in overlay.items():
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = deep_merge(result[k], v)
        else:
            result[k] = v
    return result

merged = deep_merge(target, patch)
import os
os.makedirs(os.path.dirname(target_path) or '.', exist_ok=True)
with open(target_path, 'w') as f:
    yaml.dump(merged, f, default_flow_style=False, allow_unicode=True)
PYEOF
}

py_yaml_merge_remove() {
  local target_file="$1" patch_content="$2"
  [[ -f "$target_file" ]] || return 0
  python3 - "$target_file" "$patch_content" <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    print("warning: PyYAML not installed; skipping yaml_merge removal", file=sys.stderr)
    sys.exit(0)

target_path = sys.argv[1]
patch_str   = sys.argv[2]

try:
    with open(target_path) as f:
        target = yaml.safe_load(f) or {}
except FileNotFoundError:
    sys.exit(0)

patch = yaml.safe_load(patch_str) or {}

def deep_remove(base, overlay):
    result = dict(base)
    for k, v in overlay.items():
        if k not in result:
            continue
        if isinstance(v, dict) and isinstance(result[k], dict):
            result[k] = deep_remove(result[k], v)
            if not result[k]:
                del result[k]
        else:
            del result[k]
    return result

cleaned = deep_remove(target, patch)
with open(target_path, 'w') as f:
    yaml.dump(cleaned, f, default_flow_style=False, allow_unicode=True)
PYEOF
}

py_write_dev_profile() {
  # Write a dev-named profile copy. Top-level `extends` values that point at
  # another profile artifact in the same pack are rewritten to that artifact's
  # dev name, so multi-profile packs stay self-contained in local installs.
  local src_path="$1" dest_path="$2" dev_name="$3" pkg_file="$4"
  python3 - "$src_path" "$dest_path" "$dev_name" "$pkg_file" "$PROFILE_SUFFIX" "$PACK_DIR" <<'PYEOF'
import json, os, sys

src_path, dest_path, dev_name, pkg_file, suffix, pack_dir = sys.argv[1:]

with open(src_path) as f:
    profile = json.load(f)

with open(pkg_file) as f:
    package = json.load(f)

profiles = [
    artifact
    for artifact in package.get("artifacts", [])
    if artifact.get("type") == "profile"
]

name_map = {}
for artifact in profiles:
    install_as = artifact.get("install_as")
    if install_as:
        name_map[install_as] = f"{install_as}{suffix}"
    for alias in artifact.get("aliases", []):
        name_map[alias] = f"{alias}{suffix}"

if isinstance(profile.get("extends"), str) and profile["extends"] in name_map:
    profile["extends"] = name_map[profile["extends"]]

meta = profile.get("meta")
if isinstance(meta, dict):
    meta["name"] = dev_name
else:
    profile["meta"] = {"name": dev_name}

# Dev installs wire agent plugins through symlinks back to this checkout.
# Sandbox profiles must grant the resolved target as well as ~/.codex,
# otherwise Codex can see the plugin entry but cannot read SKILL.md.
filesystem = profile.setdefault("filesystem", {})
read_entries = filesystem.setdefault("read", [])
if isinstance(read_entries, list) and pack_dir not in read_entries:
    read_entries.append(pack_dir)

os.makedirs(os.path.dirname(dest_path), exist_ok=True)
with open(dest_path, "w") as f:
    json.dump(profile, f, indent=2)
    f.write("\n")
PYEOF
}

remove_legacy_profile_symlink() {
  # Older dev-install versions wrote the registry profile name directly as a
  # symlink to the checkout. Remove only that exact legacy shape so registry or
  # user-managed profiles are not touched.
  local legacy_path="$1" src_path="$2"
  if [[ -L "$legacy_path" ]]; then
    local target
    target="$(readlink "$legacy_path")"
    if [[ "$target" == "$src_path" ]]; then
      log "rm legacy profile  $legacy_path"
      rm -f "$legacy_path"
    fi
  fi
}

# ── Per-type install handlers ────────────────────────────────────────────────

do_symlink() {
  local entry="$1"
  local link target
  link="$(jfield_expand "$entry" "link")"
  target="$(jfield_expand "$entry" "target")"
  log "symlink  $link"
  log "      -> $target"
  if (( ! DRY_RUN )); then
    mkdir -p "$(dirname "$link")"
    ln -snf "$target" "$link"
  fi
}

undo_symlink() {
  local entry="$1"
  local link
  link="$(jfield_expand "$entry" "link")"
  log "rm symlink  $link"
  doit rm -f "$link"
}

do_write_file() {
  local entry="$1"
  local source dest src_path
  source="$(jfield "$entry" "source")"
  dest="$(jfield_expand "$entry" "dest")"
  src_path="$PACK_DIR/$source"
  log "write_file  $source -> $dest"
  if (( ! DRY_RUN )); then
    mkdir -p "$(dirname "$dest")"
    cp "$src_path" "$dest"
  fi
}

undo_write_file() {
  local entry="$1"
  local dest
  dest="$(jfield_expand "$entry" "dest")"
  log "rm file  $dest"
  doit rm -f "$dest"
}

do_json_merge() {
  local entry="$1"
  local file patch patch_path patch_content
  file="$(jfield_expand "$entry" "file")"
  patch="$(jfield "$entry" "patch")"
  patch_path="$PACK_DIR/$patch"
  patch_content="$(read_and_expand "$patch_path")"
  log "json_merge  $patch -> $file"
  if (( ! DRY_RUN )); then
    mkdir -p "$(dirname "$file")"
    py_json_merge "$file" "$patch_content"
  fi
}

undo_json_merge() {
  local entry="$1"
  local file patch patch_path patch_content
  file="$(jfield_expand "$entry" "file")"
  patch="$(jfield "$entry" "patch")"
  patch_path="$PACK_DIR/$patch"
  patch_content="$(read_and_expand "$patch_path")"
  log "json_merge remove  $patch keys from $file"
  if (( ! DRY_RUN )); then
    py_json_merge_remove "$file" "$patch_content"
  fi
}

do_json_array_append() {
  local entry="$1"
  local file dot_path patch_entries key_field entries_path entries_content raw_entries_content
  file="$(jfield_expand "$entry" "file")"
  dot_path="$(jfield "$entry" "path")"
  patch_entries="$(jfield "$entry" "patch_entries")"
  key_field="$(jfield "$entry" "key_field")"
  entries_path="$PACK_DIR/$patch_entries"
  raw_entries_content="$(read_and_expand "$entries_path")"
  entries_content="$(maybe_wrap_local_shell_scripts "$raw_entries_content")"
  log "json_array_append  $patch_entries -> $file[$dot_path]"
  if (( ! DRY_RUN )); then
    mkdir -p "$(dirname "$file")"
    if [[ "$entries_content" != "$raw_entries_content" ]]; then
      py_json_array_remove "$file" "$dot_path" "$raw_entries_content" "$key_field"
    fi
    py_json_array_append "$file" "$dot_path" "$entries_content" "$key_field"
  fi
}

undo_json_array_append() {
  local entry="$1"
  local file dot_path patch_entries key_field entries_path entries_content raw_entries_content
  file="$(jfield_expand "$entry" "file")"
  dot_path="$(jfield "$entry" "path")"
  patch_entries="$(jfield "$entry" "patch_entries")"
  key_field="$(jfield "$entry" "key_field")"
  entries_path="$PACK_DIR/$patch_entries"
  raw_entries_content="$(read_and_expand "$entries_path")"
  entries_content="$(maybe_wrap_local_shell_scripts "$raw_entries_content")"
  log "json_array_remove  $patch_entries from $file[$dot_path]"
  if (( ! DRY_RUN )); then
    py_json_array_remove "$file" "$dot_path" "$entries_content" "$key_field"
    if [[ "$entries_content" != "$raw_entries_content" ]]; then
      py_json_array_remove "$file" "$dot_path" "$raw_entries_content" "$key_field"
    fi
  fi
}

do_toml_block() {
  local entry="$1"
  local file marker_id content_rel content_path block_content position
  file="$(jfield_expand "$entry" "file")"
  marker_id="$(jfield "$entry" "marker_id")"
  content_rel="$(jfield "$entry" "content")"
  position="$(jfield "$entry" "position")"
  [[ -n "$position" ]] || position="bottom"
  content_path="$PACK_DIR/$content_rel"
  block_content="$(read_and_expand "$content_path")"
  log "toml_block  $content_rel -> $file (marker: $marker_id, position: $position)"
  if (( ! DRY_RUN )); then
    mkdir -p "$(dirname "$file")"
    py_toml_block_apply "$file" "$marker_id" "$block_content" "$position"
  fi
}

undo_toml_block() {
  local entry="$1"
  local file marker_id
  file="$(jfield_expand "$entry" "file")"
  marker_id="$(jfield "$entry" "marker_id")"
  log "toml_block remove  marker '$marker_id' from $file"
  if (( ! DRY_RUN )); then
    py_toml_block_remove "$file" "$marker_id"
  fi
}

do_yaml_merge() {
  local entry="$1"
  local file patch patch_path patch_content
  file="$(jfield_expand "$entry" "file")"
  patch="$(jfield "$entry" "patch")"
  patch_path="$PACK_DIR/$patch"
  patch_content="$(read_and_expand "$patch_path")"
  log "yaml_merge  $patch -> $file"
  if (( ! DRY_RUN )); then
    mkdir -p "$(dirname "$file")"
    py_yaml_merge "$file" "$patch_content"
  fi
}

undo_yaml_merge() {
  local entry="$1"
  local file patch patch_path patch_content
  file="$(jfield_expand "$entry" "file")"
  patch="$(jfield "$entry" "patch")"
  patch_path="$PACK_DIR/$patch"
  patch_content="$(read_and_expand "$patch_path")"
  log "yaml_merge remove  $patch keys from $file"
  if (( ! DRY_RUN )); then
    py_yaml_merge_remove "$file" "$patch_content"
  fi
}

# ── Dispatch a single wiring entry ──────────────────────────────────────────

dispatch_entry() {
  local action="$1" entry="$2"
  local wtype
  wtype="$(jfield "$entry" "type")"

  if [[ "$action" == install ]]; then
    case "$wtype" in
      symlink)           do_symlink "$entry" ;;
      write_file)        do_write_file "$entry" ;;
      json_merge)        do_json_merge "$entry" ;;
      json_array_append) do_json_array_append "$entry" ;;
      toml_block)        do_toml_block "$entry" ;;
      yaml_merge)        do_yaml_merge "$entry" ;;
      *) echo "  warning: unknown wiring type '$wtype' — skipping" >&2 ;;
    esac
  else
    case "$wtype" in
      symlink)           undo_symlink "$entry" ;;
      write_file)        undo_write_file "$entry" ;;
      json_merge)        undo_json_merge "$entry" ;;
      json_array_append) undo_json_array_append "$entry" ;;
      toml_block)        undo_toml_block "$entry" ;;
      yaml_merge)        undo_yaml_merge "$entry" ;;
      *) echo "  warning: unknown wiring type '$wtype' — skipping" >&2 ;;
    esac
  fi
}

# ── Apply all wiring ─────────────────────────────────────────────────────────

apply_wiring() {
  local action="$1"   # "install" or "remove"
  local pkg_file="$PACK_DIR/package.json"

  local count
  count="$(python3 -c "
import sys, json
d = json.load(open(sys.argv[1]))
print(len(d.get('wiring', [])))
" "$pkg_file")"

  if [[ "$count" -eq 0 ]]; then
    info "  (no wiring entries)"
    return
  fi

  if [[ "$action" == "remove" ]]; then
    # Reverse order for cleaner teardown
    local indices=()
    for (( i=count-1; i>=0; i-- )); do indices+=("$i"); done
  else
    local indices=()
    for (( i=0; i<count; i++ )); do indices+=("$i"); done
  fi

  for i in "${indices[@]}"; do
    local entry
    entry="$(python3 -c "
import sys, json
d = json.load(open(sys.argv[1]))
print(json.dumps(d['wiring'][int(sys.argv[2])]))
" "$pkg_file" "$i")"
    dispatch_entry "$action" "$entry"
  done
}

# ── Profile artifact handling ────────────────────────────────────────────────
#
# Artifacts with type "profile" are installed as generated dev copies in
# $NONO_PROFILES_DIR/<install_as>-dev.json so `nono run --profile <name>-dev`
# works without shadowing registry-installed profile names. The optional
# "aliases" array creates additional dev-name copies of the same profile.

apply_profiles() {
  local action="$1"   # "install" or "remove"
  local pkg_file="$PACK_DIR/package.json"

  local entries
  entries="$(python3 -c "
import sys, json
d = json.load(open(sys.argv[1]))
profiles = [a for a in d.get('artifacts', []) if a.get('type') == 'profile']
print(json.dumps(profiles))
" "$pkg_file")"

  local count
  count="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$entries")"

  if [[ "$count" -eq 0 ]]; then
    return
  fi

  for (( i=0; i<count; i++ )); do
    local artifact install_as dev_install_as src_path dest_path legacy_path
    artifact="$(python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1])[int(sys.argv[2])]))" "$entries" "$i")"
    install_as="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('install_as',''))" "$artifact")"
    dev_install_as="${install_as}${PROFILE_SUFFIX}"
    local rel_path
    rel_path="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('path',''))" "$artifact")"
    src_path="$PACK_DIR/$rel_path"
    dest_path="$NONO_PROFILES_DIR/$dev_install_as.json"
    legacy_path="$NONO_PROFILES_DIR/$install_as.json"

    if [[ "$action" == "install" ]]; then
      log "profile  $rel_path -> $dest_path"
      if (( ! DRY_RUN )); then
        mkdir -p "$NONO_PROFILES_DIR"
        py_write_dev_profile "$src_path" "$dest_path" "$dev_install_as" "$pkg_file"
        remove_legacy_profile_symlink "$legacy_path" "$src_path"
      fi
    else
      log "rm profile  $dest_path"
      doit rm -f "$dest_path"
      if (( ! DRY_RUN )); then
        remove_legacy_profile_symlink "$legacy_path" "$src_path"
      fi
    fi

    # Handle aliases
    local aliases
    aliases="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
for a in d.get('aliases', []):
    print(a)
" "$artifact")"

    while IFS= read -r alias; do
      [[ -z "$alias" ]] && continue
      local dev_alias alias_path legacy_alias_path
      dev_alias="${alias}${PROFILE_SUFFIX}"
      alias_path="$NONO_PROFILES_DIR/$dev_alias.json"
      legacy_alias_path="$NONO_PROFILES_DIR/$alias.json"
      if [[ "$action" == "install" ]]; then
        log "profile alias  $dev_alias -> $alias_path"
        if (( ! DRY_RUN )); then
          py_write_dev_profile "$src_path" "$alias_path" "$dev_alias" "$pkg_file"
          remove_legacy_profile_symlink "$legacy_alias_path" "$src_path"
        fi
      else
        log "rm profile alias  $alias_path"
        doit rm -f "$alias_path"
        if (( ! DRY_RUN )); then
          remove_legacy_profile_symlink "$legacy_alias_path" "$src_path"
        fi
      fi
    done <<< "$aliases"
  done
}

print_profile_hint() {
  local pkg_file="$PACK_DIR/package.json"
  local profiles
  profiles="$(python3 - "$pkg_file" "$PROFILE_SUFFIX" <<'PYEOF'
import json, sys

pkg_file, suffix = sys.argv[1:]
with open(pkg_file) as f:
    package = json.load(f)

names = []
for artifact in package.get("artifacts", []):
    if artifact.get("type") != "profile":
        continue
    install_as = artifact.get("install_as")
    if install_as:
        names.append(f"{install_as}{suffix}")
    for alias in artifact.get("aliases", []):
        names.append(f"{alias}{suffix}")

for name in names:
    print(name)
PYEOF
)"

  [[ -n "$profiles" ]] || return 0

  info ""
  info "To use this locally installed pack, run your nono commands with one of these profiles:"
  while IFS= read -r profile; do
    [[ -z "$profile" ]] && continue
    info " nono run --profile $profile [...]"
  done <<< "$profiles"
}

# ── Main ─────────────────────────────────────────────────────────────────────

PACK_NAME="$(python3 -c "import json; print(json.load(open('$PACK_DIR/package.json')).get('name','?'))")"
PACK_VER="$(python3  -c "import json; print(json.load(open('$PACK_DIR/package.json')).get('version','?'))")"

printf '\ndev-install: %s  %s  v%s\n'  "$CMD" "$PACK_NAME" "$PACK_VER"
printf '  pack dir  : %s\n'            "$PACK_DIR"
printf '  namespace : %s\n'            "$NS"
printf '  dry-run   : %s\n\n'          "$([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"

case "$CMD" in
  install|update)
    info "Installing profiles..."
    apply_profiles "install"
    info "Applying wiring..."
    apply_wiring "install"
    info ""
    info "Done — $PACK_NAME v$PACK_VER installed from local source."
    print_profile_hint
    ;;
  remove)
    info "Removing wiring (reverse order)..."
    apply_wiring "remove"
    info "Removing profiles..."
    apply_profiles "remove"
    info ""
    info "Done — $PACK_NAME v$PACK_VER removed."
    ;;
esac
