#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY=ghcr.io/recmanj/dev-containers
tag=latest
dry_run=false
build_flags=()
targets=()
images=(base base-agent claude t3 codex gemini opencode pi
        distrobox/base distrobox/oxidian distrobox/ecmwf distrobox/eodh)
declare -A built=()

usage() {
    cat <<'EOF'
Usage: ./build.sh [--tag TAG] [--no-cache] [--dry-run] [IMAGE ...]

Build selected images and their parents with Podman. With no images, build all.
Images: base, base-agent, claude, t3, codex, gemini, opencode, pi,
        distrobox/base, distrobox/oxidian, distrobox/ecmwf, distrobox/eodh

  --tag TAG    Tag images and select parent images with TAG (default: latest)
  --no-cache   Rebuild without cached layers
  --dry-run    Print build commands without running them
  -h, --help   Show this help

Images stay in local Podman storage; nothing is pushed.
EOF
}

while (($#)); do
    case "$1" in
        --tag)
            if (($# < 2)) || [[ ! "$2" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]]; then
                echo 'Error: --tag requires a valid container image tag.' >&2
                exit 1
            fi
            tag="$2"
            shift 2
            ;;
        --no-cache) build_flags+=(--no-cache); shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            valid=false
            for name in "${images[@]}"; do
                [[ "$1" != "$name" ]] || valid=true
            done
            if [[ "$valid" == false ]]; then
                printf 'Error: unknown image or option: %s\n' "$1" >&2
                usage >&2
                exit 1
            fi
            targets+=("$1")
            shift
            ;;
    esac
done

if ((${#targets[@]} == 0)); then
    targets=("${images[@]}")
fi
if [[ "$dry_run" == false ]] && ! command -v podman >/dev/null 2>&1; then
    echo 'Error: podman is required to build images.' >&2
    exit 1
fi

build() {
    local name="$1"
    [[ ! -v 'built[$name]' ]] || return 0
    case "$name" in
        base-agent) build base ;;
        claude|codex|gemini|opencode|pi) build base-agent ;;
        t3) build claude ;;
        distrobox/oxidian|distrobox/ecmwf|distrobox/eodh) build distrobox/base ;;
    esac

    # Match CI's architecture and use locally built parents, fetching only
    # missing external images. TARGETARCH is also needed by base's tool installs.
    local command=(podman build --platform linux/amd64 --pull=missing --layers
        --build-arg "TARGETARCH=amd64" --build-arg "BASE_TAG=$tag"
        "${build_flags[@]}" --tag "$REGISTRY/$name:$tag" "$ROOT/$name")
    printf '\nBuilding %s:%s\n' "$name" "$tag"
    printf '%q ' "${command[@]}"
    printf '\n'
    if [[ "$dry_run" == false ]]; then
        "${command[@]}"
    fi
    built["$name"]=1
}

for target in "${targets[@]}"; do
    build "$target"
done
