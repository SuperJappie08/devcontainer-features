#!/bin/bash

set -e

FORCE_GIT_RELEASE="${FORCE_GIT_RELEASE:-"false"}"
MINIMUM_VERSION="${MINIMUM_VERSION:-"latest"}"

if [ "$(id -u)" -ne 0 ]; then
	echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

if [ "$MINIMUM_VERSION" != "latest" ]; then
	echo -e 'TODO: Minimum version'
	exit 1
fi

if type apt-get >/dev/null 2>&1; then
	echo "Installing Colcon-mixin"

	apt-get update -y
	apt-get install python3-colcon-mixin -y --no-install-recommends

	# Clean up
	rm -rf /var/lib/apt/lists/*
else
	echo "This feature only supports Debian-based for now"
	exit 1
fi
