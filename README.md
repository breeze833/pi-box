# pi-box

A containerized environment for running the [Pi coding agent](https://github.com/earendil-works/pi-coding-agent) (`@earendil-works/pi-coding-agent`) with transparent host permissions, sandboxed execution, and persistent workspace state.

Based on **Node.js 24** and **Debian Trixie** (`node:24-trixie-slim`).

---

## Features

- **Transparent File Permissions**: Dynamically matches your host `UID:GID` at startup using `gosu`. All files written to `workspace` and `pi-agent` are directly readable and editable on the host without `sudo` or permission conflicts.
- **Privileged Agent Capability**: The internal container user has passwordless `sudo` (`NOPASSWD: ALL`), allowing the agent to install needed system libraries (`sudo apt-get install -y ...`) without prompting.
- **Isolated Workspace**: By default, only the target workspace is mounted into the container.
- **Persistent State**:
  - `workspace/` &rarr; mounted to `$HOME/workspace` (holds working project files).
  - `pi-agent/` &rarr; mounted to `$HOME/.pi` (holds sessions, configuration, credentials, and extensions).
- **Batteries Included**: Pre-installed with core utilities:
  - `git`, `curl`, `wget`, `jq`, `ripgrep`, `procps`
  - `python3`, `python3-pip`, `python3-venv`
  - `sudo`, `gosu`, `ca-certificates`
- **Docker & Podman Compatible**: Works out-of-the-box with both Docker and rootless Podman.

---

## Quickstart

### 1. Clone the repository

```bash
git clone https://github.com/your-username/pi-box.git
cd pi-box
```

### 2. Configure API Keys

Create a `.env` file (copied from `.env.example`):

```bash
cp .env.example .env
```

Add your preferred provider API keys:

```bash
ANTHROPIC_API_KEY="sk-ant-..."
OPENAI_API_KEY="sk-..."
GEMINI_API_KEY="..."
```

*(Alternatively, export the environment variables directly in your host shell).*

### 3. Launch pi-box

Run the launcher script:

**Linux / macOS:**
```bash
./pi-box.sh
```

**Windows (Command Prompt / PowerShell):**
```cmd
pi-box.cmd
```

On first run, the launcher automatically builds the local container image, verifies or creates the `pi-agent/` and `workspace/` directories, and drops you into the Pi TUI.

---

## Usage & Options

### Specify a Custom Workdir

You can store the persistent state and workspace inside any folder on your host by passing `--workdir`:

```bash
./pi-box.sh --workdir /path/to/my-project
```

This will ensure `/path/to/my-project/pi-agent` and `/path/to/my-project/workspace` exist and mount them into the container.

### Force Image Rebuild

To rebuild the Docker image after modifying `Dockerfile`:

```bash
./pi-box.sh --build
```

### Pass Additional CLI Arguments to Pi

Any additional arguments passed after `--` are forwarded directly to the `pi` command:

```bash
# Print Pi version
./pi-box.sh -- --version

# Run with custom flags or print mode
./pi-box.sh -- --help
```

---

## Directory Layout

```text
pi-box/
├── Dockerfile          # Debian Trixie + Node.js 24 + Python 3 + core utils
├── entrypoint.sh       # Dynamic UID/GID mapping & gosu privilege drop
├── pi-box.sh           # Interactive CLI launcher for Linux & macOS
├── pi-box.cmd          # Interactive CLI launcher for Windows
├── .env.example        # Example environment variables for LLM APIs
├── .gitignore          # Prevents committing workspace/, pi-agent/, and .env
└── README.md           # Documentation
```

---

## Publishing to GitHub Container Registry (GHCR)

To publish pre-built multi-architecture container images to GHCR, you can add `.github/workflows/docker-publish.yml`:

```yaml
name: Build and Publish Image

on:
  push:
    branches: [ "main" ]
    tags: [ 'v*.*.*' ]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.ref_name }}
```

---

## License

[MIT](LICENSE)
