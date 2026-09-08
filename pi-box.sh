#!/usr/bin/env bash
set -e

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
WORKDIR="$PWD"
FORCE_BUILD=false
IMAGE_NAME="${PI_BOX_IMAGE:-pi-box:latest}"

usage() {
    cat << "EOF_USAGE"
Usage: pi-box.sh [OPTIONS] [-- ADDITIONAL_ARGS...]

Run the pi coding agent inside an isolated Debian container with transparent
host user file permissions and persistent state.

Options:
  -w, --workdir <DIR>    Set persistent directory scope containing "pi-agent" and "workspace"
                         (default: current working directory)
  -b, --build            Build or rebuild the container image before running
  -i, --image <NAME>     Custom container image name (default: pi-box:latest)
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

# Build image if requested or if it doesn't exist locally
IMAGE_EXISTS=false
if "$CONTAINER_BIN" image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    IMAGE_EXISTS=true
fi

if [[ "$FORCE_BUILD" = true ]] || [[ "$IMAGE_EXISTS" = false ]]; then
    echo "Building container image '$IMAGE_NAME' from '$SCRIPT_DIR'..."
    "$CONTAINER_BIN" build -t "$IMAGE_NAME" -f "${SCRIPT_DIR}/Dockerfile" "$SCRIPT_DIR"
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

# Launch interactive container
exec "$CONTAINER_BIN" run --rm -it --init     "${ENV_ARGS[@]}"     -v "${PI_AGENT_DIR}:/home/node/.pi"     -v "${WORKSPACE_DIR}:/home/node/workspace"     --workdir /home/node/workspace     "$IMAGE_NAME"     "${EXTRA_ARGS[@]}"
