FROM node:24-trixie-slim

# Avoid interactive prompts during apt install
ENV DEBIAN_FRONTEND=noninteractive

# Install core utilities, sudo, gosu, and Python 3
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    ripgrep \
    procps \
    sudo \
    gosu \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install @earendil-works/pi-coding-agent CLI globally
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Set up initial directories
RUN mkdir -p /home/node/.pi /home/node/workspace \
    && chown -R node:node /home/node

# Install entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default working directory inside the container
WORKDIR /home/node/workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["pi"]
