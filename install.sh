#!/usr/bin/env bash

VERSION="0.1.1"
RELEASE_URL="https://github.com/sgessa/lwf-pool-monitor/releases/download/v$VERSION/lwf-pool-monitor-linux-amd64.tar.gz"
DST="$HOME/lwf-pool-monitor.tar.gz"

cat << 'EOF'
                 __      ____    __    ____  _______
                |  |     \   \  /  \  /   / |   ____|
                |  |      \   \/    \/   /  |  |__
                |  |       \            /   |   __|
                |  `----.   \    /\    /    |  |
                |_______|    \__/  \__/     |__|

                         LWF Pool Monitor
EOF

echo
echo "-------------------------------------------------------"
echo "LWF Pool Monitor Installer"
echo "Version: $VERSION"
echo "Created by LWF team and dwildcash"
echo "-------------------------------------------------------"
echo

install_deps() {
  if [ ! -f /usr/bin/sudo ]; then
    echo "Install sudo before continuing. Run 'apt-get install sudo' as root user. Exiting."
    exit 1
  fi

  if ! sudo id &> /dev/null; then
    echo "Unable to gain root privileges. Exiting."
    exit 1
  fi

  DISTRO=$(awk '/^ID=/' /etc/*-release | awk -F'=' '{ print tolower($2) }')
  if [ $DISTRO != "ubuntu" ]; then
    echo "At this time only Ubuntu is supported. Exiting." && exit 1
  fi

  OS_VER=$(lsb_release -r -s)
  echo -e "Ubuntu version detected: $OS_VER\n"

  if [ $OS_VER \> 17 ]; then
    echo -n "Installing libsodium... ";
    sudo apt-get install -y libsodium23 2>&1 > /dev/null || \
      { echo "Could not install libsodium. Exiting." && exit 1; };
    echo -e "✓\n"
  else
    echo "Updating apt repository sources to install newer version of libsodium.";
    sudo apt-get install -y software-properties-common 2>&1 > /dev/null
    LC_ALL=C.UTF-8 sudo add-apt-repository --yes ppa:ondrej/php 2>&1 > /dev/null
    sudo apt-get update 2>&1 > /dev/null
    sudo apt-get install -y -qq libsodium23 || \
      { echo "Could not install libsodium. Exiting." && exit 1; };
    echo -e "✓\n"
  fi

  return 0
}

function generate_config() {
  # Backup file if already present
  if [ -f config.json ]; then
    echo "!!! Found previous config file, saving a copy to 'config.json.bak'"
    mv config.json config.json.bak
  fi

  echo
  echo "Please answer all questions to generate a new configuration file:"
  echo

  read -e -p "Enter your passphrase (12 words): " passphrase < /dev/tty
  read -e -p "Enter check interval in seconds: " -i 300 interval < /dev/tty
  read -e -p "Enter network name (lwf, lwf-t): " -i "lwf" network < /dev/tty
  read -e -p "Enter relay node host: " -i "node1.lwf.io" node_host < /dev/tty
  read -e -p "Enter relay node port: " -i "18124" node_port < /dev/tty

cat > lwf-pool-monitor/config.json <<EOF
{
  "passphrase": "$passphrase",
  "secondphrase": "",
  "autounvote": false,
  "interval": $interval,
  "buffers": {
    "daily": 12,
    "monthly": 24,
    "weekly": 48
  },
  "blacklist": [
  ],
  "net": {
    "name": "$network",
    "host": "$node_host",
    "port": $node_port
  }
}
EOF

  echo -e "\nConfiguration file saved to 'config.json'."
  return 0
}

# Installing deps
install_deps

# Download release from github in the user HOME directory
wget $RELEASE_URL -O $DST -q --show-progress

echo

if [ $? -ne 0 ]; then
  echo "Download failed. Exiting."
  exit 1
fi

# Extracting file
echo -n "Extracting release... ";
if tar zxf $DST 2>&1 > /dev/null; then
  echo -e "✓\n"
else
  echo "✗"
  echo "Extraction failed. Exiting."
  exit 1
fi

generate_config

echo
echo "Installation Completed!"
echo
echo "Enter directory:"
echo "cd ~/lwf-pool-monitor"
echo
echo "Run in foreground:"
echo "./bin/lwf foreground"
echo
echo "Or run in background:"
echo "./bin/lwf start"
