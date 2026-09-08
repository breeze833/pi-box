#!/usr/bin/env bash
set -e

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
WORKDIR="$PWD"
FORCE_BUILD=false
FORCE_PULL=false
IMAGE_NAME="${PI_BOX_IMAGE:-ghcr.io/breeze833/pi-box:latest}"

usage() {
    cat << "EOF_USAGE"
Usage: pi-box.sh [OPTIONS] [-- ADDITIONAL_ARGS...]

Run the pi coding agent inside an isolated Debian container with transparent
host user file permissions and persistent state.

Options:
  -w, --workdir <DIR>    Set persistent directory scope containing "pi-agent" and "workspace"
                         (default: current working directory)
  -p, --pull             Pull the latest container image from registry
  -b, --build            Build container image locally from Dockerfile
  -i, --image <NAME>     Custom container image name (default: ghcr.io/breeze833/pi-box:latest)
  -h, --help             Show this help message and exit

Environment Variables:
  CONTAINER_ENGINE       Specify container runtime binary (docker or podman)
  PI_BOX_IMAGE           Override default image name
  ANTHROPIC_API_KEY      Forwarded automatically if set
  OPENAI_API_KEY         Forwarded automatically if set
  GEMINI_API_KEY         Forwarded automatically if set
  OPENROUTER_API_KEY     Forwarded automatically if set
EOF_USAGE
    exit 0
}

# Parse command line options
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--workdir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --workdir requires a directory argument" >&2
                exit 1
            fi
            WORKDIR="$2"
            shift 2
            ;;
        -p|--pull)
            FORCE_PULL=true
            shift
            ;;
        -b|--build)
            FORCE_BUILD=true
            shift
            ;;
        -i|--image)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --image requires an image name" >&2
                exit 1
            fi
            IMAGE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            EXTRA_ARGS+=("$@")
            break
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# Detect container engine
CONTAINER_BIN="${CONTAINER_ENGINE:-$(command -v docker || command -v podman || true)}"
if [[ -z "$CONTAINER_BIN" ]]; then
    echo "Error: Neither 'docker' nor 'podman' found in PATH. Please install one of them." >&2
    exit 1
fi

# Ensure workdir exists and resolve absolute path
mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"

PI_AGENT_DIR="${WORKDIR}/pi-agent"
WORKSPACE_DIR="${WORKDIR}/workspace"

# Ensure subfolders exist
mkdir -p "$PI_AGENT_DIR" "$WORKSPACE_DIR"

# Check if existing directories have permission issues from a previous run
if [[ ! -w "$PI_AGENT_DIR" ]] || [[ ! -w "$WORKSPACE_DIR" ]]; then
    echo "Warning: Persistent directories are not writable by your user ($(id -un))." >&2
    echo "This usually happens if a previous container run modified their host ownership." >&2
    echo "To restore ownership on the host, run:" >&2
    echo "  podman unshare chown -R 0:0 '$PI_AGENT_DIR' '$WORKSPACE_DIR'" >&2
    echo "  (or: sudo chown -R $(id -u):$(id -g) '$PI_AGENT_DIR' '$WORKSPACE_DIR')" >&2
    echo "" >&2
fi

# Check if image exists locally
IMAGE_EXISTS=false
if "$CONTAINER_BIN" image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    IMAGE_EXISTS=true
fi

# Build, pull, or auto-fetch image
if [[ "$FORCE_BUILD" = true ]]; then
    echo "Building container image '$IMAGE_NAME' from '$SCRIPT_DIR'..."
    "$CONTAINER_BIN" build -t "$IMAGE_NAME" -f "${SCRIPT_DIR}/Dockerfile" "$SCRIPT_DIR"
elif [[ "$FORCE_PULL" = true ]]; then
    echo "Pulling latest container image '$IMAGE_NAME' from registry..."
    "$CONTAINER_BIN" pull "$IMAGE_NAME"
elif [[ "$IMAGE_EXISTS" = false ]]; then
    echo "Image '$IMAGE_NAME' not found locally. Pulling from registry..."
    if ! "$CONTAINER_BIN" pull "$IMAGE_NAME"; then
        echo "Error: Failed to pull '$IMAGE_NAME' from registry." >&2
        if [[ -f "${SCRIPT_DIR}/Dockerfile" ]]; then
            echo "Tip: You can build it locally using: $0 --build" >&2
        fi
        exit 1
    fi
fi

# Prepare environment variable arguments
ENV_ARGS=()
ENV_ARGS+=(-e "HOST_UID=$(id -u)")
ENV_ARGS+=(-e "HOST_GID=$(id -g)")
ENV_ARGS+=(-e "TERM=${TERM:-xterm-256color}")

# Check for .env file in workdir or script dir
if [[ -f "${WORKDIR}/.env" ]]; then
    ENV_ARGS+=(--env-file "${WORKDIR}/.env")
elif [[ -f "${SCRIPT_DIR}/.env" ]]; then
    ENV_ARGS+=(--env-file "${SCRIPT_DIR}/.env")
fi

# Forward common API keys if present in caller environment
for var in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY GROQ_API_KEY MISTRAL_API_KEY; do
    if [[ -n "${!var:-}" ]]; then
        ENV_ARGS+=(-e "$var")
    fi
done

# Determine container command arguments
CMD_ARGS=()
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    if [[ "${EXTRA_ARGS[0]}" == "bash" ]] || [[ "${EXTRA_ARGS[0]}" == "sh" ]] || [[ "${EXTRA_ARGS[0]}" == "pi" ]]; then
        CMD_ARGS=("${EXTRA_ARGS[@]}")
    else
        CMD_ARGS=(pi "${EXTRA_ARGS[@]}")
    fi
fi

# Launch interactive container
exec "$CONTAINER_BIN" run --rm -it --init \
    "${ENV_ARGS[@]}" \
    -v "${PI_AGENT_DIR}:/home/node/.pi" \
    -v "${WORKSPACE_DIR}:/home/node/workspace" \
    --workdir /home/node/workspace \
    "$IMAGE_NAME" \
    "${CMD_ARGS[@]}"
