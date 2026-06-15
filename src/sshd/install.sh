#!/usr/bin/env bash
# Based on:
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/vscode-dev-containers/blob/main/script-library/docs/sshd.md
# Maintainer: The VS Code and Codespaces Teams
#
# Note: You can change your user's password with "sudo passwd $(whoami)" (or just "passwd" if running as root).

SSHD_PORT="${SSHD_PORT:-"2222"}"
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
START_SSHD="${START_SSHD:-"false"}"
# TODO: Replace PASSWORD with KEY
NEW_PASSWORD="${NEW_PASSWORD:-"skip"}"
GATEWAY_PORTS="${GATEWAYPORTS:-"no"}"

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

if [ "$(id -u)" -ne 0 ]; then
	echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
	USERNAME=""
	POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
	for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
		if id -u "${CURRENT_USER}" >/dev/null 2>&1; then
			readonly USERNAME=${CURRENT_USER}
			break
		fi
	done
	if [ "${USERNAME}" = "" ]; then
		readonly USERNAME=root
	fi
elif [ "${USERNAME}" = "none" ] || ! id -u "${USERNAME}" >/dev/null 2>&1; then
	readonly USERNAME=root
fi

# Create or update a non-root user to match UID/GID.
readonly group_name="${USERNAME}"
if id -u "${USERNAME}" >/dev/null 2>&1; then
	# User exists, update if needed
	if [ "${USER_GID}" != "automatic" ] && [ "$USER_GID" != "$(id -g "$USERNAME")" ]; then
		group_name="$(id -gn "$USERNAME")"
		groupmod --gid "$USER_GID" "${group_name}"
		usermod --gid "$USER_GID" "$USERNAME"
	fi
	if [ "${USER_UID}" != "automatic" ] && [ "$USER_UID" != "$(id -u "$USERNAME")" ]; then
		usermod --uid "$USER_UID" "$USERNAME"
	fi
else
	# Create user
	if [ "${USER_GID}" = "automatic" ]; then
		groupadd "$USERNAME"
	else
		groupadd --gid "$USER_GID" "$USERNAME"
	fi
	if [ "${USER_UID}" = "automatic" ]; then
		useradd -s /bin/bash --gid "$USERNAME" -m "$USERNAME"
	else
		useradd -s /bin/bash --uid "$USER_UID" --gid "$USERNAME" -m "$USERNAME"
	fi
fi

if [ "${USERNAME}" = "root" ]; then
	readonly user_home="/root"
# Check if user already has a home directory other than /home/${USERNAME}
elif [ "/home/${USERNAME}" != "$(getent passwd "$USERNAME" | cut -d: -f6)" ]; then
	# shellcheck disable=SC2155
	readonly user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
else
	readonly user_home="/home/${USERNAME}"
	if [ ! -d "${user_home}" ]; then
		mkdir -p "${user_home}"
		chown "${USERNAME}:${group_name}" "${user_home}"
	fi
fi

# Check distro-family
. /etc/os-release
# Get an adjusted ID independent of distro variants
if [ "${ID}" = "debian" ] || [ "${ID_LIKE}" = "debian" ]; then
	readonly ADJUSTED_ID="debian"
elif [[ "${ID}" = "rhel" || "${ID}" = "fedora" || "${ID}" = "azurelinux" || "${ID}" = "mariner" || "${ID_LIKE}" = *"rhel"* || "${ID_LIKE}" = *"fedora"* || "${ID_LIKE}" = *"mariner"* ]]; then
	readonly ADJUSTED_ID="rhel"
	# shellcheck disable=SC2034
	readonly VERSION_CODENAME="${ID}${VERSION_ID}"
elif [ "${ID}" = "alpine" ]; then
	readonly ADJUSTED_ID="alpine"
else
	echo "Linux distro ${ID} not supported."
	exit 1
fi

if [ "${ADJUSTED_ID}" != "debian" ]; then
	echo "Linux distro ${ID} not supported."
	exit 1
fi

apt_get_update() {
	if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
		echo "Running apt-get update..."
		apt-get update -y
	fi
}

# Checks if packages are installed and installs them if not
check_packages() {
	if [ "${ADJUSTED_ID}" = "debian" ]; then
		if ! dpkg -s "$@" >/dev/null 2>&1; then
			apt_get_update
			apt-get -y install --no-install-recommends "$@"
		fi
	# elif [ "${ADJUSTED_ID}" = "alpine" ]; then
	# 	apk add --no-cache
	else
		echo "Linux distro ${ID} not supported."
		exit 1
	fi
}

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

# Install openssh-server openssh-client
check_packages openssh-server openssh-client lsof

# Generate password if new password set to the word "random"
if [ "${NEW_PASSWORD}" = "random" ]; then
	NEW_PASSWORD="$(openssl rand -hex 16)"
	EMIT_PASSWORD="true"
elif [ "${NEW_PASSWORD}" != "skip" ]; then
	# If new password not set to skip, set it for the specified user
	echo "${USERNAME}:${NEW_PASSWORD}" | chpasswd
fi

if [ "$(getent group ssh)" ]; then
	echo "'ssh' group already exists."
else
	echo "adding 'ssh' group, as it does not already exist."
	groupadd ssh
fi

# Add user to ssh group
if [ "${USERNAME}" != "root" ]; then
	usermod -aG ssh "${USERNAME}"
fi

# Setup sshd
mkdir -p /var/run/sshd
sed -i 's/session\s*required\s*pam_loginuid\.so/session optional pam_loginuid.so/g' /etc/pam.d/sshd
sed -i 's/#*PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i -E "s/#*\s*Port\s+.+/Port ${SSHD_PORT}/g" /etc/ssh/sshd_config
sed -i "s/#GatewayPorts no/GatewayPorts ${GATEWAY_PORTS}/g" /etc/ssh/sshd_config
sed -i "s/X11Forwarding no/X11Forwarding yes/g" /etc/ssh/sshd_config
# Need to UsePAM so /etc/environment is processed
sed -i -E "s/#?\s*UsePAM\s+.+/UsePAM yes/g" /etc/ssh/sshd_config
echo -e "\n# Extra config" >>/etc/ssh/sshd_config
if [ "${ADJUSTED_ID}" != "debian" ]; then
	echo "AcceptEnv LANG LC_*" >>/etc/ssh/sshd_config
fi
echo "AcceptEnv SSH_PWD COLORTERM" >>/etc/ssh/sshd_config

# Write to the profile
cat >>"${user_home}/.profile" <<'EOF'
if [ -n "\$SSH_PWD" ]; then
	cd "\$SSH_PWD"
fi
EOF

# Write out a scripts that can be referenced as an ENTRYPOINT to auto-start sshd and fix login environments
tee /usr/local/share/ssh-init.sh >/dev/null \
	<<'EOF'
#!/usr/bin/env bash
# This script is intended to be run as root with a container that runs as root (even if you connect with a different user)
# However, it supports running as a user other than root if passwordless sudo is configured for that same user.

set -e

sudoIf()
{
    if [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

EOF
tee -a /usr/local/share/ssh-init.sh >/dev/null \
	<<'EOF'

# ** Start SSH server **
sudoIf /etc/init.d/ssh start 2>&1 | sudoIf tee /tmp/sshd.log > /dev/null

set +e
exec "$@"
EOF
chmod +x /usr/local/share/ssh-init.sh

# If we should start sshd now, do so
if [ "${START_SSHD}" = "true" ]; then
	/usr/local/share/ssh-init.sh
fi

# Output success details
echo -e "Done!\n\n- Port: ${SSHD_PORT}\n- User: ${USERNAME}"
if [ "${EMIT_PASSWORD}" = "true" ]; then
	echo "- Password: ${NEW_PASSWORD}"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo -e "\nForward port ${SSHD_PORT} to your local machine and run:\n\n  ssh -p ${SSHD_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null ${USERNAME}@localhost\n"
