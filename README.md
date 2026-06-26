# RocketFlightViewer

Flight data viewer and configurator for the RocketPayload model rocket flight recorder (PIC16F18345-based, barometric altitude + 6-axis IMU).

## Features

- Connect via USB serial (Windows / Linux desktop) or USB serial (Android), 57600 baud
- Download and display flight data: pressure-derived altitude, 3-axis acceleration
- Flight stats summary (max altitude, max accel, burnout/apogee/landing times) auto-detected from the sample data for all payload variants
- Compare two flights side-by-side (overlaid plots and delta stats)
- PRO: select and download from up to 8 stored on-board flights (sequential slots, oldest overwritten on wraparound) — STANDARD stores 1 flight at a time
- Configure arming threshold, launch-confirm sample count, and fast-phase sample rate (50/25/10 Hz)
- View battery voltage while connected to USB
- Export flight data to CSV (raw pressure, computed altitude, accel, gyro, and ground-reference/metadata header)

## v2 Payload Hardware Compatibility Only

| Variant | Stats | Full Data Download | Plots | Multi-Flight Storage | EEPROM |
|---|---|---|---|---|---|
| STANDARD | Yes | Yes | Yes | No (1 flight) | 64KB |
| PRO | Yes | Yes | Yes | Yes (8 flights, wraparound) | 512KB |

Both variants support either of two interchangeable barometer options (LPS22HB or BMP581).

There is no longer support for hardware version v1.

## Installation

Download the latest release for your platform from the [Releases](../../releases) page.

No installation required — just run the executable (Windows/Linux) or install the APK (Android). There is no Mac build yet. An iOS build is not planned because it requires a Bluetooth connection.

## Requirements (running from source)

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x or later
- `flutter pub get`
- `flutter run` (or the platform build scripts: `build.ps1` for Windows, `build_android.ps1` for Android, `build_linux.sh` for Linux)

## Connection

**USB serial (Windows / Linux desktop):** The payload's v2 PCB has an onboard MCP2221A USB-serial chip — connect directly via USB cable, no external adapter or drivers needed. Shows up as a standard serial/COM port at 57600 baud.

**USB serial (Android):** Connect via USB type-C cable. No OTG cable required.

