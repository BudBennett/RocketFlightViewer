import 'dart:math';

// Baro pressure helpers. Both supported sensors (LPS22HB, BMP581) are
// on-chip temperature-compensated, so no per-device calibration is needed —
// they differ only in raw-counts-per-hPa scale factor.

// baroType: 1=LPS22HB (4096 LSB/hPa), 2=BMP581 (6400 LSB/hPa). Unknown/0
// defaults to LPS22HB (every unit built before BMP581 existed used it).
int lsbPerHpa(int baroType) => baroType == 2 ? 6400 : 4096;

// Pressure in hPa from raw sensor counts.
double pressureHPa(int rawPress, int baroType) =>
    rawPress / lsbPerHpa(baroType);

// Altitude above a ground reference, in meters (international barometric
// formula). Works directly on raw counts since the LSB/hPa scale factor
// cancels out in the ratio — no baroType needed.
double altitudeM(int rawPress, int groundRawPress) {
  if (groundRawPress == 0) return 0;
  return 44330.0 * (1.0 - pow(rawPress / groundRawPress, 1.0 / 5.255));
}

// Altitude above a ground reference, in feet.
double altitudeFt(int rawPress, int groundRawPress) =>
    altitudeM(rawPress, groundRawPress) * 3.28084;

// Standard sea-level pressure (1013.25 hPa) in raw sensor counts.
int standardSeaLevelRawPress(int baroType) =>
    (1013.25 * lsbPerHpa(baroType)).round();

// Estimated altitude above mean sea level, in meters, assuming standard
// atmosphere (1013.25 hPa at sea level). Used for an absolute elevation
// estimate (e.g. "arm altitude") rather than altitude above a local
// ground reference.
double altitudeMslM(int rawPress, int baroType) =>
    altitudeM(rawPress, standardSeaLevelRawPress(baroType));

// Estimated altitude above mean sea level, in feet, assuming standard
// atmosphere (1013.25 hPa at sea level).
double altitudeMslFt(int rawPress, int baroType) =>
    altitudeMslM(rawPress, baroType) * 3.28084;
