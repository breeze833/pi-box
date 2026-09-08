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

On first run, the launcher automatically pulls the pre-built image (`ghcr.io/breeze833/pi-box:latest`), verifies or creates the `pi-agent/` and `workspace/` directories, and drops you into the Pi TUI.

---

## Usage & Options

### Specify a Custom Workdir

You can store the persistent state and workspace inside any folder on your host by passing `--workdir`:

```bash
./pi-box.sh --workdir /path/to/my-project
```

This will ensure `/path/to/my-project/pi-agent` and `/path/to/my-project/workspace` exist and mount them into the container.

### Pull the Latest Image

To update to the newest published container image from GitHub Container Registry:

```bash
./pi-box.sh --pull
# or on Windows:
pi-box.cmd --pull
```

### Build Image Locally

To build or rebuild the container image locally from `Dockerfile` instead of using the registry:

```bash
./pi-box.sh --build
# or on Windows:
pi-box.cmd --build
```

### Pass Subcommands & Arguments to Pi

Any additional arguments or subcommands are forwarded directly to `pi`:

```bash
# Install an extension into .pi
./pi-box.sh install npm:pi-localllm-provider
# or on Windows:
pi-box.cmd install npm:pi-localllm-provider

# Print Pi version
./pi-box.sh --version

# Open an interactive bash shell inside the container
./pi-box.sh bash
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

## License

[MIT](LICENSE)
