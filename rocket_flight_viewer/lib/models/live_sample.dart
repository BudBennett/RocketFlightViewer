class LiveSample {
  final int rawPress;
  final int accelX; // mg (LSM6DSO32 ±32g, raw ≈ mg 1:1)
  final int accelY;
  final int accelZ;
  final int gyroX; // raw int16, ±500 dps FS
  final int gyroY;
  final int gyroZ;

  const LiveSample({
    required this.rawPress,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
  });

  double get accelXg => accelX / 1000.0;
  double get accelYg => accelY / 1000.0;
  double get accelZg => accelZ / 1000.0;

  static const double _gyroScale = 500.0 / 32768.0;
  double get gyroXdps => gyroX * _gyroScale;
  double get gyroYdps => gyroY * _gyroScale;
  double get gyroZdps => gyroZ * _gyroScale;
}

class LivePoint {
  final double timeSec;
  final LiveSample sample;
  const LivePoint({required this.timeSec, required this.sample});
}
