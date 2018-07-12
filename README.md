# LWF Pool Monitor

This tool detects if your account has voted for potential bad delegates or pools.

Optionally, you can also configure the tool to automatically unvote the pools (please use at your own risk).

Checks performed:

- voted delegate has submitted a proposal
- voted pool has sent last payout in time
- (TODO) voted delegate's node is online and forging

## Installation

Run as user with sudo privileges:

`curl -s https://raw.githubusercontent.com/sgessa/lwf-pool-monitor/master/install.sh | bash`

The installer will download the latest release and will extract it automatically in the user home directory.

If you have installed an old release and just want to upgrade, you can simply run the installer again.

If a configuration file is not present, a new one will be generated.

## Usage

**Run in foreground**

`./bin/lwf foreground`

Logs will be written to STDOUT.

![LWF Pool Monitor running in foreground](https://www.lwf.io/lwf-pool-monitor.png)

**Run as daemon**

`./bin/lwf start`

Logs can be found inside `./var/log`

**Stop daemon**

`./bin/lwf stop`

## Authors

* **Stefano Gessa** ([GitHub](https://github.com/sgessa) ~ [LD](https://www.linkedin.com/in/stefanogessa) ~ [LWF](https://explorer.lwf.io/address/6064457646976649022LWF))

## License

LWF Pool Monitor is released under the MIT license. See the [license file](LICENSE.txt).
