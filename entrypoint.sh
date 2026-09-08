#!/bin/bash
set -e

# Detect if container is running in a rootless user namespace (e.g. Rootless Podman / Rootless Docker)
# In a rootless user namespace, container UID 0 is already mapped to the host user's UID.
IS_USERNS=false
if [ -f /proc/self/uid_map ]; then
    read -r inside_uid outside_uid length _ < /proc/self/uid_map 2>/dev/null || true
    if [ "$inside_uid" = "0" ] && [ "$outside_uid" != "0" ]; then
        IS_USERNS=true
    fi
fi

# Case 1: Already running as non-root user (e.g. --user or --userns=keep-id)
if [ "$(id -u)" -ne 0 ]; then
    exec "$@"
fi

# Case 2: Running in rootless user namespace (Rootless Podman / Rootless Docker)
if [ "$IS_USERNS" = true ]; then
    # Container root (UID 0) is already mapped directly to the host user (outside_uid).
    # Any file written by container root will be owned by the host user on the host filesystem.
    # We must NOT switch to container 'node' (UID 1000) here, as container UID 1000 would map
    # to a subordinate host UID (e.g. 100999) and mutate host file ownership.
    export HOME=/home/node
    export USER=node

    # Ensure /home/node directories exist
    mkdir -p /home/node/.pi /home/node/workspace

    # Create symlinks in /root so tools checking /root resolve to /home/node
    ln -sfn /home/node/.pi /root/.pi 2>/dev/null || true
    ln -sfn /home/node/workspace /root/workspace 2>/dev/null || true

    exec "$@"
fi

# Case 3: Running in standard rootful Docker (container root == host root)
# Here we map the internal 'node' user to HOST_UID:HOST_GID and drop privileges via gosu,
# preventing host files from becoming owned by host root.
USER_ID=${HOST_UID:-1000}
GROUP_ID=${HOST_GID:-1000}

if [ "$USER_ID" -eq 0 ]; then
    exec "$@"
fi

# Adjust or create 'node' group
if getent group node >/dev/null 2>&1; then
    groupmod -o -g "$GROUP_ID" node >/dev/null 2>&1 || true
else
    groupadd -o -g "$GROUP_ID" node >/dev/null 2>&1 || true
fi

# Adjust or create 'node' user
if id -u node >/dev/null 2>&1; then
    usermod -o -u "$USER_ID" -g "$GROUP_ID" -d /home/node node >/dev/null 2>&1 || true
else
    useradd -o -u "$USER_ID" -g "$GROUP_ID" -d /home/node -s /bin/bash node >/dev/null 2>&1 || true
fi

# Ensure sudo permissions for node
echo "node ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/node
chmod 0440 /etc/sudoers.d/node

# Ensure /home/node and .pi directory ownership
mkdir -p /home/node/.pi /home/node/workspace
chown -R "$USER_ID:$GROUP_ID" /home/node/.pi /home/node 2>/dev/null || true

export HOME=/home/node
export USER=node

# Drop root privileges and execute command as 'node'
exec gosu node "$@"
