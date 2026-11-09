# shellcheck shell=bash
# Scripted "agent" for squad tests, fed to bash on stdin (cwd = task worktree):
#   bash -s -- commit | attack OTHER_TASK | forge-gpgsig | detach | lock | sleep N | exit N
set -u
export GIT_AUTHOR_NAME=agent GIT_AUTHOR_EMAIL=agent@test GIT_COMMITTER_NAME=agent GIT_COMMITTER_EMAIL=agent@test
C=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
A=$(git rev-parse --absolute-git-dir 2>/dev/null)
append() { printf 'x\n' >> "$1"; }
mvover() { printf 'x\n' > "$1.new" && mv -f "$1.new" "$1"; }
try() {   # LABEL CMD... ; prints WROTE or BLOCKED
  local what=$1; shift
  if ( "$@" ) 2>/dev/null; then echo "WROTE $what"; else echo "BLOCKED $what"; fi
}
case ${1:-} in
  commit)
    echo "agent $$" >> agent.txt
    git add agent.txt
    err=$(git commit -qm "agent commit" 2>&1 >/dev/null)
    echo "commit rc=$?"
    printf '%s\n' "$err" | sed '/^$/d; s/^/commit-stderr: /' ;;
  attack)
    other=$C/worktrees/squad-$2
    try C/config            append "$C/config"
    try C/hooks             append "$C/hooks/post-checkout"
    try C/info/exclude      append "$C/info/exclude"
    try C/HEAD              append "$C/HEAD"
    try C/index             append "$C/index"
    try C/commondir         append "$C/commondir"
    try C/config.worktree   append "$C/config.worktree"
    try other/commondir     append "$other/commondir"
    try other/rm            rm -rf "$other"
    try A/commondir         append "$A/commondir"
    try A/gitdir            append "$A/gitdir"
    try A/config.worktree   append "$A/config.worktree"
    try A/commondir-mv      mvover "$A/commondir"
    try A/commondir-rm      rm -f "$A/commondir"
    try WT/.git             append "$PWD/.git"
    try C/config-link       ln "$C/config" "$C/objects/cfg-link"
    git worktree prune 2>/dev/null
    if [ -d "$other" ]; then echo "BLOCKED prune"; else echo "WROTE prune"; fi
    # allowed by design:
    try objects             git hash-object -w --stdin <<< "agent blob"
    try A/locked            append "$A/locked"
    rm -f "$A/locked" ;;
  forge-gpgsig)
    tree=$(git rev-parse 'HEAD^{tree}'); parent=$(git rev-parse HEAD)
    obj=$(printf '%s\n' "tree $tree" "parent $parent" \
      "author a <a@a> 1700000000 +0000" "committer a <a@a> 1700000000 +0000" \
      "gpgsig -----BEGIN PGP SIGNATURE-----" " " " abc" " -----END PGP SIGNATURE-----" "" "forged" |
      git hash-object -t commit -w --stdin)
    git update-ref "refs/heads/$(git symbolic-ref --short HEAD)" "$obj"
    echo "forged $obj" ;;
  detach) git checkout -q --detach && echo detached ;;
  lock)   append "$A/locked" && echo locked ;;
  sleep)  sleep "${2:-30}" ;;
  exit)   exit "${2:-0}" ;;
  *)      echo "agent.sh: unknown behaviour: ${1:-}" >&2; exit 2 ;;
esac
