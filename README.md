# RocketFlightViewer

Flight data viewer and configurator for the RocketPayload model rocket flight computer.

## Features

- Connect via USB serial (Windows / Mac / Linux) or Bluetooth LE (Android / iOS)
- Download and display flight data: altitude, acceleration, and key flight events
- Annotated plots: launch, apogee, chute deployment, landing
- Flight stats summary (all payload variants)
- Configure launch threshold and payload settings
- Export flight data to CSV

## Payload Compatibility

| Variant | Stats | Full Data Download | Plots |
|---|---|---|---|
| STANDARD | Yes | Yes | Yes |
| LITE | Yes | — | — |

## Installation

Download the latest release for your platform from the [Releases](../../releases) page.

No installation required — just run the executable.

## Requirements (running from source)

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x or later
- `flutter pub get`
- `flutter run`

## Connection

**USB serial (laptop/desktop):** Connect via the CP2102N USB-serial adapter and level shifter.

**Bluetooth LE (phone):** Connect via the HM-10 BLE adapter accessory.
