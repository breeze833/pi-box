#!/bin/bash
set -e

# Target UID and GID passed from host (defaults to 1000:1000)
USER_ID=${HOST_UID:-1000}
GROUP_ID=${HOST_GID:-1000}

# If running as root on host, execute directly
if [ "$USER_ID" -eq 0 ]; then
    exec "$@"
fi

# Ensure group exists or adjust GID of the 'node' group
if getent group node >/dev/null 2>&1; then
    groupmod -o -g "$GROUP_ID" node >/dev/null 2>&1 || true
else
    groupadd -o -g "$GROUP_ID" node >/dev/null 2>&1 || true
fi

# Ensure user exists or adjust UID of the 'node' user
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
