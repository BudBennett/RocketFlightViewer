import 'dart:math';

// BMP384/BMP390 calibration and compensation.
// NVM layout (21 bytes from register 0x31):
//   [0-1]  nvm_par_t1  uint16 LE
//   [2-3]  nvm_par_t2  uint16 LE
//   [4]    nvm_par_t3  int8
//   [5-6]  nvm_par_p1  int16 LE
//   [7-8]  nvm_par_p2  int16 LE
//   [9]    nvm_par_p3  int8
//   [10]   nvm_par_p4  int8
//   [11-12] nvm_par_p5 uint16 LE
//   [13-14] nvm_par_p6 uint16 LE
//   [15]   nvm_par_p7  int8
//   [16]   nvm_par_p8  int8
//   [17-18] nvm_par_p9 int16 LE
//   [19]   nvm_par_p10 int8
//   [20]   nvm_par_p11 int8
class Bmp384Calib {
  final double _t1, _t2, _t3;
  final double _p1, _p2, _p3, _p4;
  final double _p5, _p6, _p7, _p8;
  final double _p9, _p10, _p11;

  const Bmp384Calib._({
    required double t1, required double t2, required double t3,
    required double p1, required double p2, required double p3, required double p4,
    required double p5, required double p6, required double p7, required double p8,
    required double p9, required double p10, required double p11,
  })  : _t1 = t1, _t2 = t2, _t3 = t3,
        _p1 = p1, _p2 = p2, _p3 = p3, _p4 = p4,
        _p5 = p5, _p6 = p6, _p7 = p7, _p8 = p8,
        _p9 = p9, _p10 = p10, _p11 = p11;

  factory Bmp384Calib.fromBytes(List<int> b) {
    assert(b.length == 21, 'Expected 21 calibration bytes, got ${b.length}');

    int u16(int off) => b[off] | (b[off + 1] << 8);
    int s16(int off) {
      final v = u16(off);
      return v >= 0x8000 ? v - 0x10000 : v;
    }
    int s8(int off) => b[off] >= 0x80 ? b[off] - 0x100 : b[off];

    // Scale factors from BMP384/BMP390 datasheet Section 8.7
    return Bmp384Calib._(
      t1:  u16(0)  * 256.0,
      t2:  u16(2)  / 1073741824.0,          // 2^30
      t3:  s8(4)   / 281474976710656.0,      // 2^48
      p1:  (s16(5) - 16384) / 1048576.0,    // (nvm - 2^14) / 2^20
      p2:  (s16(7) - 16384) / 536870912.0,  // (nvm - 2^14) / 2^29
      p3:  s8(9)   / 4294967296.0,           // 2^32
      p4:  s8(10)  / 137438953472.0,         // 2^37
      p5:  u16(11) * 8.0,                    // 2^-3
      p6:  u16(13) / 64.0,                   // 2^6
      p7:  s8(15)  / 256.0,                  // 2^8
      p8:  s8(16)  / 32768.0,                // 2^15
      p9:  s16(17) / 281474976710656.0,      // 2^48
      p10: s8(19)  / 281474976710656.0,      // 2^48
      p11: s8(20)  / 36893488147419103232.0, // 2^65
    );
  }

  // Temperature compensation — returns t_lin (°C).
  // rawTemp is the 20-bit ADC value from the sensor.
  double tLin(int rawTemp) {
    final d1 = rawTemp - _t1;
    final d2 = d1 * _t2;
    return d2 + d1 * d1 * _t3;
  }

  // Pressure compensation — returns pressure in Pa.
  // tLin is the output of [tLin(rawTemp)].
  // Use tLin=25.0 when no temperature reading is available (stored samples).
  double pressurePa(int rawPress, double tLinDeg) {
    final tl2 = tLinDeg * tLinDeg;
    final tl3 = tl2 * tLinDeg;

    final out1 = _p5 + _p6 * tLinDeg + _p7 * tl2 + _p8 * tl3;

    final adc = rawPress.toDouble();
    final out2 = adc * (_p1 + _p2 * tLinDeg + _p3 * tl2 + _p4 * tl3);

    final adc2 = adc * adc;
    final part4 = adc2 * (_p9 + _p10 * tLinDeg) + adc2 * adc * _p11;

    return out1 + out2 + part4;
  }

  // Serialize scaled parameters for CSV embedding (14 comma-separated doubles).
  String toLine() => [_t1, _t2, _t3, _p1, _p2, _p3, _p4,
                      _p5, _p6, _p7, _p8, _p9, _p10, _p11]
      .map((v) => v.toStringAsPrecision(17))
      .join(',');

  // Reconstruct from a line written by toLine().
  static Bmp384Calib? fromLine(String line) {
    try {
      final v = line.split(',').map(double.parse).toList();
      if (v.length != 14) return null;
      return Bmp384Calib._(
        t1: v[0], t2: v[1], t3: v[2],
        p1: v[3], p2: v[4], p3: v[5], p4: v[6],
        p5: v[7], p6: v[8], p7: v[9], p8: v[10],
        p9: v[11], p10: v[12], p11: v[13],
      );
    } catch (_) {
      return null;
    }
  }

  // Altitude above sea level in meters (international barometric formula).
  static double altitudeM(double pressurePa) {
    return 44330.0 * (1.0 - pow(pressurePa / 101325.0, 1.0 / 5.255));
  }

  // Altitude in feet.
  static double altitudeFt(double pressurePa) => altitudeM(pressurePa) * 3.28084;
}
