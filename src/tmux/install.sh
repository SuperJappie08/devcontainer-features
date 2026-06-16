#!/usr/bin/env bash

if [ "$(id -u)" -ne 0 ]; then
	echo 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

if command -v tmux; then
	echo "tmux was already installed"
	exit 0
fi

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

if ! [[ "${ADJUSTED_ID}" == "debian" || "${ADJUSTED_ID}" == "alpine" ]]; then
	echo "Linux distro ${ID} not supported."
	exit 1
fi

case $ADJUSTED_ID in
	debian)
		# Ensure apt is in non-interactive to avoid prompts
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -y
		apt-get install tmux -y --no-install-recommends
		rm -rf /var/lib/apt/lists/*
		;;
	alpine)
		apk add tmux
		rm -rf /var/cache/apk/*
		;;
	rhel)
		rm -rf /var/cache/dnf/*
		rm -rf /var/cache/yum/*
		;;
esac
