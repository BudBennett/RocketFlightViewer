import 'dart:math';

class FlightSample {
  final int timeMs;
  final int rawPress;
  final int accelX; // mg (LSM6DSO32 ±32g, raw ≈ mg 1:1)
  final int accelY;
  final int accelZ;
  final int gyroX; // raw int16, ±500 dps FS
  final int gyroY;
  final int gyroZ;
  final int rawTemp;       // BMP384 raw 20-bit temperature ADC value
  final double? altitudeM; // AGL metres — populated from CSV column; null for raw device downloads

  const FlightSample({
    required this.timeMs,
    required this.rawPress,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.rawTemp,
    this.altitudeM,
  });

  double get timeSec => timeMs / 1000.0;

  double get accelMagG {
    final x = accelX / 1000.0;
    final y = accelY / 1000.0;
    final z = accelZ / 1000.0;
    return sqrt(x * x + y * y + z * z);
  }

  // ±500 dps / 32768 LSB
  static const double gyroScaleDps = 500.0 / 32768.0;
}
