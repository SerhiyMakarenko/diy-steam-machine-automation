# DIY Steam Machine Automation
The DIY Steam Machine Automation repo contains configuration files to make the Bazzite system behave like a console: waking up the PC and TV on controller wake-up, and suspending the PC and TV when the controller is powered off.

## Hardware Setup
My hardware setup consists of the following devices:
- [DIY Steam Machine](https://serhiis.blog/2026/08/12/diy-steam-machine-hardware.html);
- Sony BRAVIA XR65A80J OLED TV;
- Valve Steam Controller;
- 8BitDo Pro 3 Controller;
- 2 x 8BitDo Ultimate 2.4G Controllers.

The whole idea was to make all this hardware function like a game console. The main goal was that the event of powering on any of the controllers mentioned above is to:
- Wake a PC;
- Wake a TV;
- Switch the TV to the HDMI input to which the PC is connected.

The table below describes each step in detail.

| Event                           | What happens                                                                                                                                 |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Any controller powers on        | The PC wakes from suspend (USB wake). About 12 s later, once the network is back, the TV powers on and switches to the configured HDMI port. |
| An 8BitDo controller powers off | After a short settle delay, if no other controller (8BitDo or Steam) is on: TV off, then suspend.                                            |
| The Steam Controller powers off | Same rule, detected by polling the puck because it never re-enumerates on USB.                                                               |

## Installation
Here are the commands you need to run to perform the initial installation on a fresh Bazzite system.
```bash
git clone https://github.com/SerhiyMakarenko/diy-steam-machine-automation.git && cd diy-steam-machine-automation
sudo make install
```
Small note: `make` must be available. Check with the following command:
```bash
command -v make
```
If it is missing, run:
```bash
sudo rpm-ostree install make
```
and reboot.

## Configuring the TV
On the TV (one time, the setting survives the PC being reinstalled): `Settings -> Network ->
IP control -> Authentication -> "Normal and Pre-Shared Key"`, choose a key on the TV, then use the same value as `TV_PSK` in the config, and
keep Remote start on "Powered on by apps". After `sudo make install`, run `sudoedit /etc/steam-machine/steam-machine.conf` and set `TV_IP` and `TV_PSK` (the repo ships placeholders).

## Settings

The file `/etc/steam-machine/steam-machine.conf` is installed once, never overwritten by `make install`. Here is the description of each parameter you will find in the configuration file.

| Key                                                                 | Meaning                                                         |
| ------------------------------------------------------------------- | --------------------------------------------------------------- |
| `TV_IP`, `TV_PORT`, `TV_PSK`                                        | TV address and Pre-Shared Key                                   |
| `TV_HDMI_PORT`                                                      | HDMI port selected after power-on                               |
| `TV_ON_ATTEMPTS`, `TV_OFF_ATTEMPTS`, `TV_RETRY_DELAY`, `TV_TIMEOUT` | Retry budget for power commands                                 |
| `TV_HDMI_ATTEMPTS`, `TV_HDMI_DELAY`                                 | Retry budget for the input switch                               |
| `SUSPEND_DELAY`                                                     | Seconds the 8BitDo path waits before deciding                   |
| `STEAM_SILENT_PROBES`                                               | Silent ~2 s probes before the Steam Controller counts as off    |

Format: `KEY=value`, one per line. The file is never executed: Python parses it, and the shell scripts read only `SUSPEND_DELAY` and `STEAM_SILENT_PROBES` with `sed`, so special characters in `TV_PSK` need no quoting. It contains the PSK secret, so the installer sets its permissions to `root:wheel 0640`. Edit it with `sudo`.

## What Files Get Installed

| Path                  | File                                     | Role                                                                           |
| --------------------- | ---------------------------------------- | ------------------------------------------------------------------------------ |
| `/usr/local/bin`      | `tv-control`                             | TV power and HDMI input over the Sony REST API (Python, standard library only) |
|                       | `controllers-active`                     | "Is any controller on?" shared by both suspend triggers                        |
|                       | `suspend-with-tv-off`                    | TV off first, then suspend (the order matters)                                 |
|                       | `8bitdo-suspend`                         | Started by udev when an 8BitDo controller drops off                            |
|                       | `steam-controller-watch`                 | Service that polls the Steam Controller puck                                   |
| `/etc/udev/rules.d`   | `70-usb-hub-wakeup.rules`                | Lets USB hubs wake the PC (how the 8BitDo wake works)                          |
|                       | `72-8bitdo-suspend.rules`           | 8BitDo controller power off triggers `8bitdo-suspend` script                                       |
|                       | `73-steam-controller-wakeup.rules`       | Enables wake on the Steam Controller puck                                      |
|                       | `75-bluetooth-no-wakeup.rules`           | Optional: stops the Bluetooth radio waking the PC                              |
| `/etc/systemd/system` | `steam-controller-watch.service`         | Runs the watcher                                                               |
|                       | `systemd-suspend.service.d/tv-wake.conf` | Switches the TV on after resume                                                |

Scripts find each other relative to their own location, and the units and rules are
rendered with the install prefix, so `make install PREFIX=/opt/x` works too.

Hardware IDs are constants at the top of `scripts/controllers-active` and in the `udev/` rules:
- 8BitDo `2dc8` (idle product `3109`);
- Steam Controller puck `28de:1304`;
- Bluetooth radio `8087:0029`.
Change them there if you swap controllers.

### Scripts
The script `/usr/local/bin/tv-control` switches a Sony Bravia TV on or off and selects an HDMI input. It talks to the TV’s IP Control REST API using Pre-Shared-Key authentication. Standard library only: no pip, no virtualenv.

- `tv-control on`: power on, then switch to the configured HDMI port;
- `tv-control off`: power off the TV;
- `tv-control hdmi`: only switch to the configured HDMI port.
Settings are read from the `/etc/steam-machine/steam-machine.conf` configuration file (override the path with the `STEAM_MACHINE_CONFIG` environment variable).

The script `/usr/local/bin/controllers-active` reports whether any gamepad is currently powered on. Here are the supported arguments:
- `controllers-active [any|steam|8bitdo]`: if `exit 0`, then a controller is on; if `exit 1`, then none of them are connected.
The 2.4 GHz 8BitDo dongles (vendor `2dc8`) report product ID `3109` while no controller is on; any other 2dc8 hidraw device means one is active.
The Steam Controller Puck (vendor `28de`) never re-enumerates, but its controller-slot interface streams ~270 reports/s while a controller is on and goes silent when it is off, so we sample the hidraw interfaces.

The script `/usr/local/bin/suspend-with-tv-off` switches the TV off, then suspends the PC. The order matters: once suspend is requested, NetworkManager tears the network down almost immediately, so the TV command has to finish first. A failed TV command must never stop the PC from suspending.

The script `/usr/local/bin/8bitdo-suspend` is started by udev through systemd-run when an 8BitDo dongle’s hidraw interface disappears, which is what powering a controller off looks like. Waits for the state change to settle, then suspends unless any controller (8BitDo or Steam) is still on.

The script `/usr/local/bin/steam-controller-watch` is a long-running service: suspend the PC and TV when the Steam Controller powers off. The Steam Controller Puck never re-enumerates on USB, so udev cannot see the controller turning off. Instead, we poll: once the controller has been silent for `STEAM_SILENT_PROBES` consecutive probes after being active, treat it as off. Only an `active -> silent` transition counts, so booting or resuming with the controller already off never triggers a suspend.

### udev Rules
The udev rule `/etc/udev/rules.d/70-usb-hub-wakeup.rules` lets USB root hubs and hubs wake the PC from suspend. The 8BitDo dongles expose no wakeup attribute of their own; waking the PC works through their hub’s connect/disconnect events, so the hubs themselves must be allowed to wake it.

The udev rule `/etc/udev/rules.d/72-8bitdo-suspend.rules` re-checks before running the `8bitdo-suspend` script because the 8BitDo dongle’s hidraw interface disappears when its controller powers off and also when it powers on.

The udev rule `/etc/udev/rules.d/73-steam-controller-wakeup.rules` enables USB wakeup for the Steam Controller Puck so a button press on the controller can wake the PC because it ships with USB wakeup disabled.

The udev rule `/etc/udev/rules.d/75-bluetooth-no-wakeup.rules` keeps the Intel AX200 Bluetooth radio (8087:0029) from waking the PC. The file is optional: delete it if you want Bluetooth devices to wake the machine.

### systemd Units
The systemd unit `/etc/systemd/system/steam-controller-watch.service` suspends the PC and TV when the Steam Controller powers off.

The file `/etc/systemd/system/systemd-suspend.service.d/tv-wake.conf` is a drop-in for systemd-suspend.service: switch the TV on once the PC has resumed. Detached `--no-block` so the TV’s retry loop is not cut off by systemd’s stop-post timeout; the network needs ~12 s to come back after resume.

## Make Targets

| Target                                        | What it does                                                 |
| --------------------------------------------- | ------------------------------------------------------------ |
| `sudo make install`                           | Install and activate everything                              |
| `make diff`                                   | Show how the repo differs from what is installed             |
| `make check`                                  | Syntax checks and a scan for hardcoded user paths            |
| `sudo make uninstall` / `purge`               | Remove the install (`purge` also deletes the config)         |
| `make install DESTDIR=/tmp/stage CONF_GROUP=` | Staged install, no root, nothing activated                   |

## Troubleshooting

```bash
journalctl -t steam-controller-watch -b         # what the Steam watcher decided
systemctl status steam-controller-watch
sudo tv-control on                              # try the TV by hand
sudo controllers-active steam; echo $?          # 0 = on, 1 = off
journalctl -b | grep -i tv-control              # output of the post-resume TV-on
```

* TV does nothing: run `sudo tv-control on` and read the message. "still holds the placeholder" means `/etc/steam-machine/steam-machine.conf` hasn't been edited yet. "HTTP 403" fails immediately and means a wrong PSK or IP control disabled on the TV. Network errors are retried for `TV_ON_ATTEMPTS`/`TV_OFF_ATTEMPTS` × `TV_RETRY_DELAY` seconds (about 30 s by default) before giving up.
* Wake stops working: list wake state with `for d in /sys/bus/usb/devices/*; do [ -f $d/power/wakeup ] && echo "$(basename $d) $(cat $d/power/wakeup) $(cat $d/product 2>/dev/null)"; done`
* Always suspend with `suspend-with-tv-off`, never a bare `systemctl suspend`: the network goes down as soon as suspend is requested, and the TV-off call would lose that race.
