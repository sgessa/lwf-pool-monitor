#!/usr/bin/env bash

VERSION="0.1.2"
RELEASE_URL="https://github.com/sgessa/lwf-pool-monitor/releases/download/v$VERSION/lwf-pool-monitor-linux-amd64.tar.gz"
DST="$HOME/lwf-pool-monitor.tar.gz"

# Define default value
node_host_m="node1.lwf.io"
node_port_m=18124
node_host_t="testnode1.lwf.io"
node_port_t=18101

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

  if [ $OS_VER \> 18 ]; then
    echo -n "Installing libsodium... ";
    sudo apt-get install -y libsodium23 2>&1 > /dev/null || \
      { echo "Could not install libsodium23. Exiting." && exit 1; };
    echo -e "✓\n"
  else
    echo "Updating apt repository sources to install newer version of libsodium.";
    sudo apt-get install -y software-properties-common 2>&1 > /dev/null
    LC_ALL=C.UTF-8 sudo add-apt-repository --yes ppa:ondrej/php 2>&1 > /dev/null
    sudo apt-get update 2>&1 > /dev/null
    sudo apt-get install -y -qq libsodium23 || \
      { echo "Could not install libsodium23. Exiting." && exit 1; };
    echo -e "✓\n"
  fi

  return 0
}

check_localnode() {
  networks=()

  if [[ `netstat -tl | grep 18124 | wc -l` -ge 1 ]]; then
    echo -e "LWF mainnet node detected\n"
    networks+=("local lwf")
  fi

  if [[ `netstat -tl | grep 18101 | wc -l` -ge 1 ]]; then
    echo -e "LWF testnet node detected\n"
    networks+=("local lwf-t")
  fi
}

# function to display menus
configure_network() {
  options=("lwf" "lwf-t" "quit")
  options=("${networks[@]}" "${options[@]}")

  echo -e "Networks available:\n"

  PS3="Select network: "
  select opt in "${options[@]}"; do
    case $opt in
      "local lwf")
        network="lwf"
        node_host="localhost"
        node_port=$node_port_m
        break
        ;;
      "local lwf-t")
        network="lwf-t"
        node_host="localhost"
        node_port=$node_port_t
        break
        ;;
      "lwf")
        network="lwf"
        node_host=$node_host_m
        node_port=$node_port_m
        break
        ;;
      "lwf-t")
        network="lwf-t"
        node_host=$node_host_t
        node_port=$node_port_t
        break
        ;;
      "quit")
        exit
        break
        ;;
      *) echo "invalid option $REPLY";;
    esac
  done
}

function generate_config() {
  cd ~/lwf-pool-monitor

  # Backup file if already present
  if [ -f config.json ]; then
    echo "!!! Found previous config file, saving a copy to 'config.json.bak'"
    mv config.json config.json.bak
  fi

  echo
  echo "Please answer all questions to generate a new configuration file:"
  echo

  # Check if passphrase contains 12 words
  while [ `echo "$passphrase" | wc -w` -lt 12 ]; do
    read -e -p "Enter your passphrase (12 words): " passphrase < /dev/tty

    if [ `echo "$passphrase" | wc -w` -lt 12 ]; then
      echo "Please enter a valide passphrase with 12 words!"
    fi
  done

  read -e -p "Enter check interval in seconds: " -i 300 interval < /dev/tty

cat > config.json <<EOF
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

# Extracting filea
echo -n "Extracting release... ";
if tar zxf $DST 2>&1 > /dev/null; then
  echo -e "✓\n"
else
  echo "✖"
  echo "Extraction failed. Exiting."
  exit 1
fi

check_localnode
configure_network
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
