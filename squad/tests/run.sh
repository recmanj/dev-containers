#!/usr/bin/env bash
# SC2016: the single-quoted bash -c scripts expand their own "$1"/"$2".
# shellcheck disable=SC2016
# Tests for squad/agent-squad.  Usage: bash squad/tests/run.sh
#   Tier 1: bash + git only (bwrap parts skip when bwrap does not work).
#   Tier 2: needs tmux; skipped with a message when tmux is missing.
# Never reaches the real podman: squad/tests/bin/podman is first on PATH.
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
SQ=$ROOT/squad/agent-squad
TB=$ROOT/squad/tests/bin
AGENT=$ROOT/squad/tests/agent.sh
T=$(cd -P -- "$(mktemp -d "${TMPDIR:-/tmp}/squad-test.XXXXXX")" && pwd)
SYS_PATH=$PATH

mkdir -p "$T/home"
export PATH="$TB:$PATH" HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 TMUX_TMPDIR="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export FAKE_PODMAN_LOG=$T/podman.log
unset TMUX FAKE_LOG FAKE_HIDE FAKE_PS_BUSY FAKE_PS_FAIL DEV_CONTAINER_EXTRA_VOLUMES \
  AGENT_SQUAD_AGENT AGENT_SQUAD_TRUST_CONFIG AGENT_SQUAD_STOP_TIMEOUT
cleanup() { if command -v tmux >/dev/null; then tmux kill-server 2>/dev/null; fi; rm -rf "$T"; }
trap cleanup EXIT

if [ "$(command -v podman)" != "$TB/podman" ]; then
  echo "abort: podman resolves to $(command -v podman), not the fake" >&2; exit 2
fi

PASS=0 FAILS=0 SKIPS=0
ok()   { PASS=$((PASS + 1)); echo "ok   $*"; }
bad()  { FAILS=$((FAILS + 1)); echo "FAIL $*"; }
skip() { SKIPS=$((SKIPS + 1)); echo "skip $*"; }
run()  { OUT=$("$@" 2>&1 </dev/null); RC=$?; }   # sets OUT and RC; no stdin, so prompts never block
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$3], got [$2]"; fi; }
not0() { if [ "$RC" -ne 0 ]; then ok "$1"; else bad "$1: expected failure"; show; fi; }
is0()  { if [ "$RC" -eq 0 ]; then ok "$1"; else bad "$1: rc=$RC"; show; fi; }
has()  { case $OUT in *"$2"*) ok "$1";; *) bad "$1: [$2] not in output"; show;; esac; }
hasline(){ case $'\n'"$OUT"$'\n' in *$'\n'"$2"$'\n'*) ok "$1";; *) bad "$1: line [$2] not in output"; show;; esac; }
hasnt(){ case $OUT in *"$2"*) bad "$1: [$2] in output"; show;; *) ok "$1";; esac; }
yes()  { if "${@:2}" >/dev/null; then ok "$1"; else bad "$1"; fi; }
show() { printf '%s\n' "$OUT" | sed 's/^/    | /'; }

# newrepo NAME: fresh repo R with one commit; sets R, C
newrepo() {
  R=$T/$1; C=$R/.git
  git init -q -b main "$R" && echo base > "$R/file" &&
    git -C "$R" add file && git -C "$R" commit -qm init
}
sq() { (cd "$R" && "$SQ" "$@") </dev/null; }
task() { WT=$R/.claude/worktrees/squad-$1; A=$C/worktrees/squad-$1; VOL=dev-container-$(printf '%s' "$WT" | shasum -a 256 | cut -c1-12); }
wtcommit() { echo "$2" > "$WT/$1" && git -C "$WT" add "$1" && git -C "$WT" commit -qm "add $1"; }
# podman calls as one line each ("volume rm NAME", "ps -a -q ...")
podman_calls() { awk 'BEGIN{RS="";FS="\n"} {l=$1; for(i=2;i<=NF;i++) l=l" "$i; print l}' "$FAKE_PODMAN_LOG" 2>/dev/null; }
count() { podman_calls | grep -c "$1"; }
BWRAP=''; if bwrap --ro-bind / / true 2>/dev/null; then BWRAP=1; fi
# in_container TASK BEHAVIOUR...: run the scripted agent the way a squad session would
in_container() { (cd "$R/.claude/worktrees/squad-$1" && FAKE_HIDE=$R DEV_CONTAINER_EXTRA_VOLUMES="$(cd "$R" && "$SQ" mounts "$1")" fake-container agent "${@:2}"); }

echo "== tier 1"

t1_names_layouts() {
  newrepo r1
  local n
  for n in '' -x a/b .. 'a b' a:b "$(printf 'a%.0s' {1..41})"; do
    run sq new "$n" --no-start; not0 "1 name '$n' rejected"
  done
  run sq new "$(printf 'a%.0s' {1..40})" --no-start; is0 "1 40-char name accepted"
  git init -q --bare "$T/bare"; run bash -c 'cd "$1" && "$2" ls' _ "$T/bare" "$SQ"
  not0 "1 bare repo refused"
  git init -q --separate-git-dir="$T/sep.git" "$T/sep"; run bash -c 'cd "$1" && "$2" ls' _ "$T/sep" "$SQ"
  not0 "1 .git-file layout refused"; has "1 .git-file message" "unsupported layout"
  git init -q "$T/co:lon"; run bash -c 'cd "$1" && "$2" ls' _ "$T/co:lon" "$SQ"
  not0 "1 path with ':' refused"
}

t2_new() {
  newrepo r2; task t1
  run sq new t1 -a fake --no-start; is0 "2 new --no-start"
  yes "2 worktree exists" test -f "$WT/file"
  is "2 branch tracks base" "$(git -C "$R" rev-parse --abbrev-ref 'squad/t1@{upstream}')" main
  yes "2 config.worktree empty" test -f "$A/config.worktree" -a ! -s "$A/config.worktree"
  is "2 main checkout clean" "$(git -C "$R" status --porcelain)" ""
  run sq new t1 --no-start; not0 "2 existing task refused"
  run bash -c 'source "$1"; tmux_escape a "semi;" "x;y" ";"; printf "[%s]" "${ESCAPED[@]}"' _ "$SQ"
  is "2 tmux_escape escapes only a trailing ;" "$OUT" '[a][semi\;][x;y][\;]'
  run sq new t9 -a nosuch; not0 "2 unknown agent refused"; yes "2 ... before touching git" test ! -e "$R/.claude/worktrees/squad-t9"
}

t3_mounts() {
  newrepo r3; task t1; sq new t1 --no-start >/dev/null 2>&1
  local exp="$C:$C:ro
$C/objects:$C/objects
$C/refs:$C/refs
$C/logs:$C/logs
$A:$A
$A/commondir:$A/commondir:ro
$A/gitdir:$A/gitdir:ro
$A/config.worktree:$A/config.worktree:ro
$WT/.git:$WT/.git:ro"
  is "3 mounts golden list" "$(sq mounts t1)" "$exp"
}

t4_container() {
  if [ -z "$BWRAP" ]; then skip "4 bwrap container simulation (bwrap unusable)"; return; fi
  newrepo r4; task t1
  sq new t1 --no-start >/dev/null 2>&1; sq new t2 --no-start >/dev/null 2>&1
  run in_container t1 commit
  has "4 in-container commit exits 0" "commit rc=0"
  is "4 commit visible on host" "$(git -C "$R" log -1 --format=%s squad/t1)" "agent commit"
  local noise; noise=$(printf '%s\n' "$OUT" | grep '^commit-stderr:' | grep -v 'packed-refs.lock')
  is "4 commit stderr is only packed-refs.lock noise" "$noise" ""
  case $OUT in *packed-refs.lock*) echo "     (packed-refs.lock noise present, as documented)";; esac
  run in_container t1 attack t2
  local w
  for w in C/config C/hooks C/info/exclude C/HEAD C/index C/commondir C/config.worktree other/commondir \
           other/rm A/commondir A/gitdir A/config.worktree A/commondir-mv A/commondir-rm WT/.git C/config-link prune; do
    hasline "4 blocked: $w" "BLOCKED $w"
  done
  hasline "4 allowed: objects" "WROTE objects"; hasline "4 allowed: A/locked" "WROTE A/locked"
  yes "4 other task intact" test -f "$C/worktrees/squad-t2/commondir"
  run bash -c 'cd "$1" && FAKE_HIDE=$2 fake-container agent commit' _ "$WT" "$R"
  hasnt "4 without the variable git fails inside" "commit rc=0"
  run in_container t1 lock; yes "4 agent can lock its worktree" test -f "$A/locked"
  run sq rm t1 --force; is0 "4 rm --force removes a locked worktree"; yes "4 ... gone" test ! -e "$WT"
}

t5_harden() {
  newrepo r5; task t1; sq new t1 --no-start >/dev/null 2>&1
  printf '* diff=x\n' > "$WT/.gitattributes"; git -C "$WT" add .gitattributes
  wtcommit agentfile agent
  local m=$T/mark.sh h
  printf '#!/bin/sh\necho "$0 $*" >> %s/marker\nexit 0\n' "$T" > "$m"; chmod +x "$m"
  mkdir -p "$C/hooks"
  for h in post-checkout post-merge pre-merge-commit commit-msg prepare-commit-msg reference-transaction; do
    cp "$m" "$C/hooks/$h"
  done
  git config --file "$C/config" core.fsmonitor "$m"
  git config --file "$C/config" core.pager "$m"
  git config --file "$C/config" diff.external "$m"
  git config --file "$C/config" diff.x.textconv "$m"
  git config --file "$C/config" core.worktree "$T/elsewhere"
  echo untracked > "$R/dirty.txt"
  run sq status t1; is0 "5 status"
  run sq diff t1;   is0 "5 diff"; has "5 diff content" "+agent"
  run sq diff t1 --stat; is0 "5 diff --stat"
  run sq merge t1;  is0 "5 merge"
  has "5 merge lists sensitive paths" ".gitattributes"; has "5 merge warns about dirty checkout" "uncommitted changes"
  yes "5 merge result in MAIN" test -f "$R/agentfile"
  run sq rm t1; is0 "5 rm"
  yes "5 no planted program ran" test ! -e "$T/marker"
  git config --file "$C/config" --unset core.worktree
  rm -f "$T/marker"

  # 5d: forged gpgsig commit + planted gpg.program
  newrepo r5d; task t1; sq new t1 --no-start >/dev/null 2>&1; wtcommit f2 x
  git config --file "$C/config" gpg.program "$m"
  git config --file "$C/config" merge.verifySignatures true
  run in_container t1 forge-gpgsig; has "5d agent forged a gpgsig commit" "forged"
  run sq diff t1; is0 "5d diff"
  run sq status t1; is0 "5d status"
  run sq merge t1; is0 "5d merge of forged commit"
  yes "5d planted gpg.program did not run" test ! -e "$T/marker"

  # 5t: a tag shadowing the target branch must not hide sensitive paths
  newrepo r5t; task t1; sq new t1 --no-start >/dev/null 2>&1
  wtcommit Makefile 'all:'
  git -C "$R" tag main squad/t1
  run sq merge t1; is0 "5t merge with tag 'main' present"
  has "5t sensitive path listed despite tag 'main'" $'changed paths that can run code on your machine:\nMakefile'

  # 5r: merge refuses while the agent's container runs, and merges the checked commit
  newrepo r5r; task t1; sq new t1 --no-start >/dev/null 2>&1; wtcommit f5r x
  echo 1 > "$T/busy"
  run env FAKE_PS_BUSY="$T/busy" bash -c 'cd "$1" && "$2" merge t1' _ "$R" "$SQ"
  not0 "5r merge refuses while a container runs"; has "5r ... says stop" "agent-squad stop t1"
  yes "5r ... nothing merged" test ! -f "$R/f5r"
  local tip; tip=$(git -C "$R" rev-parse squad/t1)
  run sq merge t1; is0 "5r merge"; has "5r prints the commit" "$tip"
  is "5r merged exactly that commit" "$(git -C "$R" rev-parse HEAD^2)" "$tip"

  # 5u: diff and merge warn about work the agent left uncommitted
  newrepo r5u; task t1; sq new t1 --no-start >/dev/null 2>&1
  echo edit >> "$WT/file"; echo new > "$WT/scratch.txt"
  run sq diff t1; is0 "5u diff"; has "5u diff warns" "uncommitted changes, not shown"
  has "5u ... lists the edit" " M file"; has "5u ... lists the new file" "?? scratch.txt"
  run sq merge t1; has "5u merge warns" "not merged"
  newrepo r5v; task t1; sq new t1 --no-start >/dev/null 2>&1; wtcommit f x
  run sq diff t1; hasnt "5u clean worktree: no warning" "uncommitted"

  # gap: HARDEN has no empty diff.external, so a plain diff still works
  newrepo r5e
  run bash -c 'source "$1"; cd "$2"; g log -p -1 >/dev/null && g show >/dev/null' _ "$SQ" "$R"
  is0 "5 g log -p / g show work under HARDEN"
}

t6_config_check() {
  local key
  for key in filter.x.clean merge.x.driver include.path; do
    newrepo "r6-${key//./-}"; task t1; sq new t1 --no-start >/dev/null 2>&1; wtcommit f y
    : > "$T/empty.cfg"
    git config --file "$C/config" "$key" "$T/empty.cfg"
    run sq new t2 --no-start; not0 "6 $key: new refuses"; has "6 $key: names key" "$key"
    run sq status t1; not0 "6 $key: status refuses"
    run sq merge t1;  not0 "6 $key: merge refuses"
    run sq rm t1;     not0 "6 $key: rm refuses"
    run env AGENT_SQUAD_TRUST_CONFIG=1 bash -c 'cd "$1" && "$2" status t1' _ "$R" "$SQ"
    is0 "6 $key: override passes"
  done
}

t7_replace() {
  newrepo r7; task t1; sq new t1 --no-start >/dev/null 2>&1; wtcommit f2 real
  git -C "$R" replace "$(git -C "$R" rev-parse squad/t1:f2)" "$(echo fake | git -C "$R" hash-object -w --stdin)"
  run sq diff t1
  has "7 diff shows real content" "+real"; hasnt "7 diff ignores replacement" "+fake"; has "7 warns" "refs/replace"
}

t8_tampered() {
  newrepo r8; task t1; sq new t1 --no-start >/dev/null 2>&1
  echo "gitdir: $T/elsewhere" > "$WT/.git"
  run sq start t1 -a fake; not0 "8 start refuses tampered .git"
  run sq status t1; not0 "8 status refuses"
  run sq rm t1; not0 "8 rm refuses"
  run sq rm t1 --force; not0 "8 rm --force refuses"
  yes "8 worktree kept" test -d "$WT"
}

t9_rm() {
  newrepo r9; task t1; sq new t1 --no-start >/dev/null 2>&1
  (cd "$WT" && FAKE_PODMAN_LOG=$T/wrap.log "$ROOT/base/dev-container" >/dev/null)
  local want; want=$(grep -oE '^dev-container-[0-9a-f]{12}(-venv|-node_modules)?' "$T/wrap.log" | sort -u)
  is "9a dev-container uses VOL, -venv, -node_modules" "$(printf '%s\n' "$want" | wc -l | tr -d ' ')" 3
  : > "$T/wrap.log"; (cd "$WT" && FAKE_PODMAN_LOG=$T/wrap.log "$ROOT/claude/claude-container" >/dev/null)
  is "9a claude-container volumes match" "$(grep -oE '^dev-container-[0-9a-f]{12}-(venv|node_modules)' "$T/wrap.log" | sort -u)" \
     "$(printf '%s\n' "$want" | grep -E -- '-(venv|node_modules)$')"
  echo dirty >> "$WT/file"
  run sq rm t1; not0 "9a rm refuses dirty worktree"; has "9a says why" "uncommitted"
  : > "$FAKE_PODMAN_LOG"
  run sq rm t1 --force; is0 "9a rm --force"; yes "9a worktree gone" test ! -e "$WT" -a ! -e "$A"
  is "9a removed exactly the wrappers' volumes" "$(podman_calls | sed -n 's/^volume rm //p' | sort)" "$want"
  yes "9a branch kept" git -C "$R" rev-parse -q --verify squad/t1
  sq new t1 --no-start >/dev/null 2>&1
  run sq rm t1 --delete-branch; is0 "9a rm --delete-branch"; has "9a prints sha" "deleted squad/t1 (was "
  yes "9a branch gone" test -z "$(git -C "$R" branch --list squad/t1)"

  # 9a' rm must not lose untracked files or trust a failing git status
  git -C "$R" config status.showUntrackedFiles no
  sq new t1 --no-start >/dev/null 2>&1; echo new > "$WT/untracked.txt"
  run sq rm t1; not0 "9a' rm refuses untracked files despite showUntrackedFiles=no"
  yes "9a' ... file kept" test -f "$WT/untracked.txt"
  git -C "$R" config --unset status.showUntrackedFiles
  rm "$WT/untracked.txt"; printf 'garbage' > "$A/index"
  run sq rm t1; not0 "9a' rm refuses when git status fails"; has "9a' ... says why" "git status failed"
  yes "9a' ... worktree kept" test -d "$WT"
  run sq rm t1 --force; is0 "9a' rm --force still works with a broken index"

  # 9b container wait
  sq new t1 --no-start >/dev/null 2>&1; : > "$FAKE_PODMAN_LOG"; echo 2 > "$T/busy"
  run env FAKE_PS_BUSY="$T/busy" bash -c 'cd "$1" && "$2" rm t1 --force' _ "$R" "$SQ"
  is0 "9b rm --force waits for containers"; is "9b ps polled 3 times" "$(count '^ps ')" 3
  yes "9b removed after wait" test ! -e "$WT"
  sq new t1 --no-start >/dev/null 2>&1; : > "$FAKE_PODMAN_LOG"; echo 99 > "$T/busy"
  run env FAKE_PS_BUSY="$T/busy" AGENT_SQUAD_STOP_TIMEOUT=1 bash -c 'cd "$1" && "$2" rm t1 --force' _ "$R" "$SQ"
  not0 "9b rm --force aborts on timeout"
  yes "9b worktree, admin dir and branch kept" test -d "$WT" -a -d "$A"
  yes "9b ... branch" git -C "$R" rev-parse -q --verify squad/t1
  is "9b no volume rm" "$(count '^volume rm')" 0
  has "9b names container" deadbeef; has "9b names VOL" "$VOL "; has "9b names -venv" "$VOL-venv"; has "9b names -node_modules" "$VOL-node_modules"
  : > "$FAKE_PODMAN_LOG"; echo 1 > "$T/busy"
  run env FAKE_PS_BUSY="$T/busy" bash -c 'cd "$1" && "$2" rm t1' _ "$R" "$SQ"
  not0 "9b plain rm refuses at once while busy"; is "9b ... one ps call" "$(count '^ps ')" 1
  run env FAKE_PS_FAIL=1 bash -c 'cd "$1" && "$2" rm t1 --force' _ "$R" "$SQ"
  not0 "9b podman ps failure is an error"; has "9b ... with a clear message" "podman ps failed"
  yes "9b ... nothing removed" test -d "$WT"

  # A/locked (the agent can write it)
  echo agent > "$A/locked"
  run sq rm t1; is0 "9 plain rm removes a locked clean worktree"
  sq new t1 --no-start >/dev/null 2>&1; echo agent > "$A/locked"; echo d >> "$WT/file"
  run sq rm t1 --force; is0 "9 rm --force removes a locked dirty worktree"

  # 9c podman absent
  if PATH=$SYS_PATH command -v podman >/dev/null; then
    skip "9c podman absent (a real podman is on PATH)"
  else
    sq new t1 --no-start >/dev/null 2>&1
    run env PATH="$SYS_PATH" bash -c 'cd "$1" && "$2" rm t1 --force' _ "$R" "$SQ"
    is0 "9c rm without podman"; has "9c prints volume names" "volumes not removed: $VOL $VOL-venv"
  fi
}

t10_wrappers() {
  local w d=$T/wdir exp
  mkdir -p "$d"
  for w in claude/claude-container codex/codex-container gemini/gemini-container opencode/opencode-container base/dev-container; do
    rm -f "$T"/w-*.log
    if git -C "$ROOT" cat-file -e "HEAD:$w" 2>/dev/null; then
      git -C "$ROOT" show "HEAD:$w" > "$T/orig-wrapper"
      (cd "$d" && FAKE_PODMAN_LOG=$T/w-orig.log bash "$T/orig-wrapper" x y >/dev/null)
    fi
    (cd "$d" && FAKE_PODMAN_LOG=$T/w-unset.log "$ROOT/$w" x y >/dev/null)
    (cd "$d" && FAKE_PODMAN_LOG=$T/w-set.log DEV_CONTAINER_EXTRA_VOLUMES=$'/a:/a\n\n/b c:/b c:ro\n' "$ROOT/$w" x y >/dev/null)
    if [ -f "$T/w-orig.log" ]; then
      is "10a $w: argv unchanged without the variable" "$(cat "$T/w-unset.log")" "$(cat "$T/w-orig.log")"
    else
      skip "10a $w: no committed version to compare"
    fi
    exp=$(awk -v nm="$d/node_modules" '{print} $0 ~ (":" nm "$") {print "-v"; print "/a:/a"; print "-v"; print "/b c:/b c:ro"}' "$T/w-unset.log")
    is "10a $w: specs follow the node_modules mount, blank lines ignored" "$(cat "$T/w-set.log")" "$exp"
  done

  # 10b wrapper lookup (functions reached by sourcing the script)
  wr() { run bash -c 'source "$1"; wrapper "$2"' _ "$SQ" "$1"; }
  wr dev; is0 "10b dev"; is "10b dev -> base/dev-container" "$OUT" "$ROOT/base/dev-container"
  mkdir -p "$T/shadow"; printf '#!/bin/sh\n# DEV_CONTAINER_EXTRA_VOLUMES\n' > "$T/shadow/claude-container"; chmod +x "$T/shadow/claude-container"
  PATH="$T/shadow:$PATH" wr claude; is "10b repo copy wins over PATH" "$OUT" "$ROOT/claude/claude-container"
  wr fake; is "10b fake via PATH" "$OUT" "$TB/fake-container"
  wr nosuch; not0 "10b nosuch refused"; has "10b nosuch message" "no wrapper nosuch-container"
  printf '#!/bin/sh\n' > "$T/shadow/nomark-container"; chmod +x "$T/shadow/nomark-container"
  PATH="$T/shadow:$PATH" wr nomark; not0 "10b wrapper without marker refused"; has "10b marker message" "lacks"
  local sw=$T/x/.claude/worktrees/squad-x
  mkdir -p "$sw/squad"; cp "$TB/fake-container" "$sw/foo-container"
  wr "$sw/foo-container"; not0 "10b wrapper inside squad worktree refused"
  cp "$SQ" "$sw/squad/agent-squad"; run "$sw/squad/agent-squad" help
  not0 "10b agent-squad copy inside squad worktree refused"
}

t11_syntax() {
  local f
  for f in "$SQ" "$TB/podman" "$TB/fake-container" "$AGENT" "$0" "$ROOT"/{claude/claude,codex/codex,gemini/gemini,opencode/opencode}-container "$ROOT/base/dev-container"; do
    run bash -n "$f"; is0 "11 bash -n ${f#"$ROOT"/}"
  done
  if command -v shellcheck >/dev/null; then
    run shellcheck -x "$SQ"; is0 "11 shellcheck agent-squad"
  else
    skip "11 shellcheck not installed"
  fi
}

t12_detached() {
  newrepo r12; task t1; sq new t1 --no-start >/dev/null 2>&1; wtcommit f2 x
  git -C "$R" checkout -q --detach
  local h0; h0=$(git -C "$R" rev-parse HEAD)
  run sq merge t1; not0 "12 merge refuses detached HEAD"
  has "12 says detached" "detached"; has "12 jj hint" "jj new"
  is "12 HEAD unchanged" "$(git -C "$R" rev-parse HEAD)" "$h0"
  run sq new t3 --no-start; is0 "12 new on detached HEAD"
  is "12 t3 based on HEAD sha" "$(git -C "$R" rev-parse squad/t3)" "$h0"
  run git -C "$R" rev-parse -q --verify 'squad/t3@{upstream}'; not0 "12 t3 has no upstream"
  (cd "$WT" && bash -s -- detach < "$AGENT" >/dev/null)
  run sq ls; has "12 ls shows (detached)" "(detached)"
  run sq status t1; is0 "12 status still works"
}

t13_exclude() {
  newrepo r13
  sq new a --no-start >/dev/null 2>&1; sq new b --no-start >/dev/null 2>&1
  is "13 exclude appended exactly once" "$(grep -c '^/\.claude/worktrees/$' "$C/info/exclude")" 1
}

t14_other_worktree() {
  newrepo r14; task t5
  git -C "$R" worktree add -q "$R/.claude/worktrees/feat" -b feat
  local F=$R/.claude/worktrees/feat
  run bash -c 'cd "$1" && "$2" new t5 --no-start' _ "$F" "$SQ"; is0 "14 new from a non-squad worktree"
  is "14 based on that worktree's branch" "$(git -C "$R" rev-parse --abbrev-ref 'squad/t5@{upstream}')" feat
  wtcommit f5 x
  local m0; m0=$(git -C "$R" rev-parse main)
  run bash -c 'cd "$1" && "$2" merge t5' _ "$F" "$SQ"; not0 "14 merge without --into refused"; has "14 hint" "--into"
  run bash -c 'cd "$1" && "$2" merge t5 --into main' _ "$F" "$SQ"; not0 "14 --into a branch not checked out here refused"
  run bash -c 'cd "$1" && "$2" merge t5 --into feat' _ "$F" "$SQ"; is0 "14 merge --into feat"
  is "14 merged into feat" "$(git -C "$R" rev-parse feat^2)" "$(git -C "$R" rev-parse squad/t5)"
  is "14 main untouched" "$(git -C "$R" rev-parse main)" "$m0"
}

t1_names_layouts; t2_new; t3_mounts; t4_container; t5_harden; t6_config_check
t7_replace; t8_tampered; t9_rm; t10_wrappers; t11_syntax; t12_detached; t13_exclude; t14_other_worktree

echo "== tier 2 (tmux)"
wait_for() { local _; for _ in $(seq 50); do "$@" && return 0; sleep 0.1; done; return 1; }
sess_path() { tmux display-message -p -t "=$1:" '#{session_path}' 2>/dev/null; }
ls_state() { sq ls | awk -v n="$1" '$1 == n {print $2 ($2 == "exited" ? " " $3 : "")}'; }

tier2() {
  newrepo r20; task t2
  local log=$HOME/fake-squad-t2.log
  run sq new t2 -a fake -- agent sleep 30 'semi;'; is0 "T2.1 new starts a session"
  yes "T2.1 session exists" wait_for test -s "$log"
  is "T2.1 session_path is WT" "$(sess_path squad-r20-t2)" "$WT"
  OUT=$(cat "$log" 2>/dev/null)
  has "T2.1 stdin is a TTY" stdin_tty=1; has "T2.1 stdout is a TTY" stdout_tty=1
  has "T2.1 cwd" "cwd=$WT"; has "T2.1 PWD" "PWD=$WT"
  has "T2.1 volumes = mounts" "volumes<<
$(sq mounts t2)
>>"
  has "T2.1 argv intact incl. trailing ;" "arg=agent
arg=sleep
arg=30
arg=semi;"
  is "T2.2 ls running" "$(ls_state t2)" running

  task t3; run sq new t3 -a fake -- agent exit 3; is0 "T2.2 new t3"
  yes "T2.2 exited 3" wait_for test "$(ls_state t3)" = "exited 3"
  run sq start t3 -a fake -- agent sleep 30; is0 "T2.2 start relaunches a dead pane without stop"
  is "T2.2 t3 running again" "$(ls_state t3)" running

  run sq stop t2; is0 "T2.2 stop"; is "T2.2 stopped" "$(ls_state t2)" stopped
  run sq start t2 -a fake -- agent sleep 30; is0 "T2.2 start after stop"; is "T2.2 running" "$(ls_state t2)" running
  echo 99 > "$T/busy"
  run env FAKE_PS_BUSY="$T/busy" AGENT_SQUAD_STOP_TIMEOUT=1 bash -c 'cd "$1" && "$2" stop t3' _ "$R" "$SQ"
  is0 "9b stop exits 0 on container timeout"; has "9b stop warns" "podman stop"

  run sq new xy -a fake -- agent sleep 30; is0 "T2.3 new xy"
  run sq stop x; not0 "T2.3 stop x does not match xy"
  yes "T2.3 xy survives" tmux has-session -t "=squad-r20-xy"
  sq new t4 --no-start >/dev/null 2>&1
  tmux new-session -d -s squad-r20-t4 -c "$T" sleep 60
  run sq start t4 -a fake; not0 "T2.3 start refuses a foreign same-named session"
  run sq stop t4; not0 "T2.3 stop refuses a foreign same-named session"
  yes "T2.3 foreign session survives" tmux has-session -t "=squad-r20-t4"

  task t2
  run sq rm t2; not0 "T2.4 rm refuses while running"
  run sq rm t2 --force; is0 "T2.4 rm --force kills the session"
  yes "T2.4 session gone" test -z "$(sess_path squad-r20-t2)"
}
if command -v tmux >/dev/null; then tier2; else skip "tier 2: tmux not installed"; fi

echo "== $PASS passed, $FAILS failed, $SKIPS skipped"
[ "$FAILS" -eq 0 ]
