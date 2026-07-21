#!/usr/bin/env bash

set -e

INSTALL_VERSION="${VERSION:-"latest"}"
USERNAME="${USERNAME:-"automatic"}"
USER_UID="${USERUID:-"automatic"}"
USER_GID="${USERGID:-"automatic"}"

if [ "$(id -u)" -ne 0 ]; then
	echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

# NOTE: Most of the user mananagement stuff is copied from common-utils

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
	USER_UID=0
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

# Bring in ID, ID_LIKE, VERSION_ID, VERSION_CODENAME
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

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install curl jq ca-certificates unzip -y --no-install-recommends

# Clean up
rm -rf /var/lib/apt/lists/*

if [ "$INSTALL_VERSION" != "latest" ]; then
	readonly release_version="tags/$INSTALL_VERSION"
else
	readonly release_version="$INSTALL_VERSION"
fi

url=$(curl -L -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2026-03-10" \
	"https://api.github.com/repos/redhat-developer/vscode-xml/releases/${release_version}" | jq ".assets[] | select(.name|endswith(\"linux-$(arch).zip\")).browser_download_url" | cut -d '"' -f 2)
curl -fLo /tmp/lemminx-linux.zip "$url"
mkdir -p /opt/lemminx-linux/bin

mkdir -p "${user_home}/.local/bin"
unzip /tmp/lemminx-linux.zip -d /tmp
mv "/tmp/lemminx-linux-$(arch)" "/opt/lemminx-linux/bin/lemminx-linux"
chmod +x "/opt/lemminx-linux/bin/lemminx-linux"
chown "${USERNAME}:${group_name}" "${user_home}/.local"
chown "${USERNAME}:${group_name}" "${user_home}/.local/bin"
ln -s /opt/lemminx-linux/bin/lemminx-linux "${user_home}/.local/bin/lemminx-linux"
rm -rf /tmp/lemminx*
