#!/usr/bin/env bash

set -e

FORCE_GIT_RELEASE="${FORCE_GIT_RELEASE:-"false"}"
MINIMUM_VERSION="${MINIMUM_VERSION:-"latest"}"
DEFAULT_EDITOR="${DEFAULT_EDITOR:-"true"}"
USERNAME="${USERNAME:-"automatic"}"

if [ "$(id -u)" -ne 0 ]; then
	echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

if [ "$MINIMUM_VERSION" != "latest" ]; then
	echo -e 'TODO: Minimum version'
	exit 1
fi

if type apt-get >/dev/null 2>&1; then
	echo "Installing Helix"

	apt-get update -y

	if apt-cache show helix >/dev/null && [ "${FORCE_GIT_RELEASE}" = "false" ]; then
		apt-get install helix -y --no-install-recommends
	else
		apt-get install -y --no-install-recommends curl jq ca-certificates
		url=$(curl -L -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2026-03-10" \
			https://api.github.com/repos/helix-editor/helix/releases/latest | jq '.assets[] | select(.name|endswith("deb")).browser_download_url' | cut -d '"' -f 2)
		curl -fLo /tmp/helix.deb "$url"

		apt-get install /tmp/helix.deb -y --no-install-recommends

		rm -rf /tmp/helix.deb
	fi

	# Clean up
	rm -rf /var/lib/apt/lists/*
else
	echo "This feature only supports Debian-based for now"
	exit 1
fi

# If in automatic mode, determine if a user already exists, if not use vscode
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
	if [ "${_REMOTE_USER}" != "root" ]; then
		USERNAME="${_REMOTE_USER}"
	else
		USERNAME=""
		POSSIBLE_USERS=("devcontainer" "vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
		for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
			if id -u "${CURRENT_USER}" >/dev/null 2>&1; then
				USERNAME=${CURRENT_USER}
				break
			fi
		done
		if [ "${USERNAME}" = "" ]; then
			USERNAME=vscode
		fi
	fi
elif [ "${USERNAME}" = "none" ]; then
	USERNAME=root
	# shellcheck disable=SC2034
	USER_UID=0
	# shellcheck disable=SC2034
	USER_GID=0
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
	user_home="/root"
# Check if user already has a home directory other than /home/${USERNAME}
elif [ "/home/${USERNAME}" != "$(getent passwd "$USERNAME" | cut -d: -f6)" ]; then
	user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
else
	user_home="/home/${USERNAME}"
	if [ ! -d "${user_home}" ]; then
		mkdir -p "${user_home}"
		chown "${USERNAME}:${group_name}" "${user_home}"
	fi
fi

if [ "${DEFAULT_EDITOR}" = "true" ]; then
	echo "export EDITOR=hx" >>"${user_home}/.profile"
fi
