#!/usr/bin/env bash
set -euo pipefail
cleanup=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")/../bin/agent-cleanup")
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
old=946684800
root_id=11111111-1111-4111-8111-111111111111
child_id=22222222-2222-4222-8222-222222222222
other_id=33333333-3333-4333-8333-333333333333
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

fixture() {
  case_root=$(mktemp -d "$tmp/case.XXXXXX")
  mkdir -p "$case_root"/{bin,home/.codex/sessions,home/.claude/projects/proj,home/.local/share/claude/versions}
  printf '[]\n' > "$case_root/threads.json"
  cat > "$case_root/bin/codex" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == app-server ]] || exit 1
while IFS= read -r request; do
  id=$(jq -r '.id // empty' <<< "$request")
  [[ -n $id ]] || continue
  method=$(jq -r .method <<< "$request")
  printf '%s\n' "$request" >> "$FIXTURE/api.log"
  case $method in
    initialize) result='{}' ;;
    thread/list)
      ancestor=$(jq -r '.params.ancestorThreadId // ""' <<< "$request")
      archived=$(jq -r .params.archived <<< "$request")
      offset=$(jq -r '.params.cursor // "0"' <<< "$request")
      result=$(jq -c --arg ancestor "$ancestor" --argjson archived "$archived" --argjson offset "$offset" '
        [.[] | select((.archived // false) == $archived) | select($ancestor == "" or .parent == $ancestor)] |
        {data: .[$offset:$offset+1], nextCursor: (if length > $offset+1 then ($offset+1|tostring) else null end)}' "$FIXTURE/threads.json") ;;
    thread/read)
      sid=$(jq -r .params.threadId <<< "$request")
      result=$(jq -ce --arg sid "$sid" '{thread: (.[] | select(.id==$sid))}' "$FIXTURE/threads.json") ;;
    thread/delete)
      sid=$(jq -r .params.threadId <<< "$request")
      while IFS= read -r path; do [[ ! -f $path ]] || rm -- "$path"; done < <(jq -r --arg sid "$sid" '.[] | select(.id==$sid or .parent==$sid) | .path' "$FIXTURE/threads.json")
      jq --arg sid "$sid" '[.[] | select(.id!=$sid and .parent!=$sid)]' "$FIXTURE/threads.json" > "$FIXTURE/next.json"
      mv "$FIXTURE/next.json" "$FIXTURE/threads.json"
      result='{}' ;;
    *) exit 1 ;;
  esac
  jq -cn --argjson id "$id" --argjson result "$result" '{id:$id,result:$result}'
done
STUB
  chmod +x "$case_root/bin/codex"
}

run_cleanup() {
  HOME="$case_root/home" CODEX_HOME="$case_root/home/.codex" CLAUDE_CONFIG_DIR="$case_root/home/.claude" \
    XDG_DATA_HOME="$case_root/home/.local/share" XDG_CACHE_HOME="$case_root/home/.cache" \
    FIXTURE="$case_root" PATH="$case_root/bin:$PATH" bash "$cleanup" > "$case_root/output" 2>&1
}

transcript() {
  local path=$1
  printf '{"timestamp":"2000-01-01T00:00:00Z"}\n' > "$path"
  touch -d "@$old" "$path"
}

thread() {
  local sid=$1 parent=${2:-} archived=${3:-false} updated=${4:-$old} path
  path=$case_root/home/.codex/sessions/$sid.jsonl
  transcript "$path"
  jq --arg id "$sid" --arg parent "$parent" --arg path "$path" --argjson updated "$updated" --argjson archived "$archived" \
    '. + [{id:$id,parent:$parent,path:$path,updatedAt:$updated,archived:$archived}]' "$case_root/threads.json" > "$case_root/next.json"
  mv "$case_root/next.json" "$case_root/threads.json"
}

fixture
thread "$root_id"
thread "$child_id" "$root_id" false "$(date +%s)"
thread "$other_id" '' true
run_cleanup || { cat "$case_root/output"; fail 'Codex cleanup'; }
[[ -f $case_root/home/.codex/sessions/$root_id.jsonl ]] || fail 'old parent of recent child removed'
[[ ! -f $case_root/home/.codex/sessions/$other_id.jsonl ]] || fail 'archived old thread retained'
printf 'PASS: Codex pagination, archived sessions and recent-descendant protection\n'

fixture
thread "$root_id"
thread "$child_id" "$root_id"
run_cleanup || { cat "$case_root/output"; fail 'old tree cleanup'; }
[[ $(jq -s '[.[]|select(.method=="thread/delete")]|length' "$case_root/api.log") == 1 ]] || fail 'tree deleted more than once'
printf 'PASS: old Codex tree deleted once via supported API\n'

fixture
claude=$case_root/home/.claude
transcript "$claude/projects/proj/$root_id.jsonl"
transcript "$claude/projects/proj/$child_id.jsonl"
printf '{"timestamp":"2099-01-01T00:00:00Z"}\n' >> "$claude/projects/proj/$child_id.jsonl"
touch -d "@$old" "$claude/projects/proj/$child_id.jsonl"
mkdir -p "$claude/file-history/$root_id" "$claude/projects/proj/memory"
printf 'keep\n' > "$claude/projects/proj/memory/MEMORY.md"
touch -d "@$old" "$claude/file-history/$root_id"
printf '{"sessionId":"%s","timestamp":946684800000}\n' "$root_id" > "$claude/history.jsonl"
chmod 600 "$claude/history.jsonl"
jq -n --arg old "$root_id" --arg recent "$child_id" '{entries:[{sessionId:$old},{sessionId:$recent}]}' > "$claude/projects/proj/sessions-index.json"
jq -n --arg sid "$root_id" '{projects:{proj:{lastSessionId:$sid,lastSessionMetrics:{tokens:1},allowedTools:["Read"]}}}' > "$claude/.claude.json"
run_cleanup || { cat "$case_root/output"; fail 'Claude cleanup'; }
[[ ! -e $claude/projects/proj/$root_id.jsonl && ! -d $claude/file-history/$root_id ]] || fail 'old Claude assets retained'
[[ -f $claude/projects/proj/$child_id.jsonl && -f $claude/projects/proj/memory/MEMORY.md ]] || fail 'recent session or memory deleted'
[[ $(stat -c %a "$claude/history.jsonl") == 600 ]] || fail 'history permissions changed'
jq -e --arg sid "$child_id" '.entries==[{sessionId:$sid}]' "$claude/projects/proj/sessions-index.json" >/dev/null || fail 'stale session index'
jq -e '.projects.proj=={allowedTools:["Read"]}' "$claude/.claude.json" >/dev/null || fail 'stale config reference'
run_cleanup || { cat "$case_root/output"; fail 'repeat cleanup with empty history'; }
printf 'PASS: Claude timestamps, assets, references, memory, permissions and repeated cleanup\n'

fixture
claude=$case_root/home/.claude
transcript "$claude/projects/proj/$root_id.jsonl"
mkdir "$claude/sessions"
jq -n --arg sid "$root_id" --argjson pid "$$" '{pid:$pid,sessionId:$sid}' > "$claude/sessions/live.json"
run_cleanup || { cat "$case_root/output"; fail 'live session cleanup'; }
[[ -f $claude/projects/proj/$root_id.jsonl ]] || fail 'live idle Claude session deleted'
printf 'PASS: running idle Claude session protected\n'

fixture
versions=$case_root/home/.local/share/claude/versions
for v in 2.1.8 2.1.9 2.1.10 2.1.11 2.1.12; do printf '#!/bin/bash\nexit 0\n' > "$versions/$v"; chmod +x "$versions/$v"; done
touch "$versions/2.1.13"
ln -s "$versions/2.1.10" "$case_root/bin/claude"
run_cleanup || { cat "$case_root/output"; fail 'binary cleanup'; }
[[ -f $versions/2.1.10 && -f $versions/2.1.9 ]] || fail 'current or predecessor deleted'
[[ ! -f $versions/2.1.12 && ! -f $versions/2.1.11 && ! -f $versions/2.1.8 ]] || fail 'unused binary retained'
[[ -f $versions/2.1.13 ]] || fail 'incomplete install removed'
printf 'PASS: current binary plus predecessor, including rollback selection\n'

fixture
claude=$case_root/home/.claude
transcript "$claude/projects/proj/$root_id.jsonl"
printf '{"sessionId":"%s"}\n' "$root_id" > "$claude/history.jsonl"
mkdir "$claude/history.jsonl.lock"
run_cleanup & cleanup_pid=$!
sleep 0.2
printf '{"sessionId":"new","display":"concurrent prompt"}\n' >> "$claude/history.jsonl"
rmdir "$claude/history.jsonl.lock"
wait "$cleanup_pid" || { cat "$case_root/output"; fail 'concurrent history cleanup'; }
jq -e '.sessionId=="new" and .display=="concurrent prompt"' "$claude/history.jsonl" >/dev/null || fail 'concurrent prompt lost'
[[ ! -d $claude/history.jsonl.lock ]] || fail 'metadata lock leaked'
printf 'PASS: concurrent history writer preserved and lock released\n'

fixture
claude=$case_root/home/.claude
transcript "$claude/projects/proj/$root_id.jsonl"
mkdir "$claude/file-history"
ln -s "$tmp" "$claude/file-history/$root_id"
if run_cleanup; then fail 'symlinked sidecar accepted'; fi
[[ -f $claude/projects/proj/$root_id.jsonl ]] || fail 'data deleted before symlink refusal'
printf 'PASS: symlinked sidecars refused before deletion\n'

# Source helpers in an isolated subshell; this does not invoke cleanup.
(
  # shellcheck source=../bin/agent-cleanup
  source "$cleanup"
  [[ $(ac_month_ago 2024-03-31 00:00:00) == "$(date -u -d 2024-02-29 +%s)" ]] || fail 'month-end cutoff'
  [[ $(ac_month_ago 2025-01-10 00:00:00) == "$(date -u -d 2024-12-10 +%s)" ]] || fail 'year-boundary cutoff'
  ac_tmp=$(mktemp -d "$tmp/versions.XXXXXX")
  versions=$ac_tmp/releases
  mkdir "$versions"
  for v in 2.1.9 2.1.10 2.1.11 2.1.12; do printf '#!/bin/bash\nexit 0\n' > "$versions/$v"; chmod +x "$versions/$v"; done
  declare -A ac_binaries=()
  ac_processes() { ac_binaries=(["$versions/2.1.12"]=1 ["$versions/2.1.10"]=1); }
  ac_selections() { :; }
  ac_versions "$versions"
  [[ -f $versions/2.1.12 && -f $versions/2.1.10 && ! -e $versions/2.1.11 && ! -e $versions/2.1.9 ]] || fail 'extra backup retained with two versions in use'
)
printf 'PASS: calendar-month boundaries and two versions already in use\n'
