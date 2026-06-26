Rocket Flight Viewer - Linux
=============================

Prerequisites (one-time setup)
--------------------------------
1. Install the serial port runtime library:

     Ubuntu / Debian / Raspberry Pi OS:
       sudo apt install libserialport0

     Fedora:
       sudo dnf install libserialport

     Arch:
       sudo pacman -S libserialport

2. Add your user to the dialout group so the app can open serial ports:

     sudo usermod -aG dialout $USER

   Then log out and log back in (or reboot) for this to take effect.
   The app will start but won't see any ports until you do this.

Running
--------
Unzip to any folder, then run:

   cd bundle
   ./rocket_flight_viewer

Or create a desktop shortcut pointing to the rocket_flight_viewer binary
inside the bundle/ folder. Do not move the binary out of bundle/ — it
depends on the lib/ and data/ folders alongside it.

Connecting the payload
-----------------------
Connect via USB using a CP2102N USB-to-serial adapter. The device will
appear as /dev/ttyUSB0 (or similar). Select it from the port dropdown
in the app.

Troubleshooting
---------------
- No ports listed: confirm dialout group membership (groups $USER) and
  that the USB adapter is plugged in.
- Permission denied on /dev/ttyUSB0: the dialout group change has not
  taken effect yet — reboot and try again.
