# shairport-updater
Script to update Shairport-Sync and NQPTP

## Usage

Update and rebuild manually:

    ./update-airplay.sh [--force]

Install as a command and schedule a daily update (run on the Raspberry Pi):

    sudo ./install.sh

After installing, run `sudo update-airplay` at any time. The daily run is handled by the `update-airplay.timer` systemd timer.

If an AirPlay session is connected when the script runs, it skips the update and exits. The next scheduled run will try again.

- Check the schedule: `systemctl list-timers update-airplay.timer`
- View logs: `journalctl -u update-airplay.service`
- Remove the command and timer: `sudo ./install.sh --uninstall`
