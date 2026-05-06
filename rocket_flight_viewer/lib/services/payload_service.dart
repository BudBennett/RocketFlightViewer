import '../models/bmp384_calib.dart';
import '../models/flight_data.dart';
import '../models/flight_sample.dart';
import '../models/flight_stats.dart';
import '../models/live_sample.dart';
import 'serial_service.dart';

class PayloadService {
  final SerialService _serial;

  PayloadService(this._serial);

  // Returns (thrMg, lpfSetting, fastPhaseMaxS) or null on failure.
  Future<(int, int, int)?> getConfig() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x43])) return null; // 'C'
    final data = await _serial.readBytes(4, timeoutMs: 2000);
    if (data == null) return null;
    return ((data[0] << 8) | data[1], data[2], data[3]); // thrMg, lpfSetting, fastPhaseMaxS
  }

  Future<bool> setConfig(int thrMg, int lpfSetting, int fastPhaseMaxS) async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x53, (thrMg >> 8) & 0xFF, thrMg & 0xFF, lpfSetting & 0xFF, fastPhaseMaxS & 0xFF])) return false; // 'S'
    final data = await _serial.readBytes(1, timeoutMs: 2000);
    return data != null && data[0] == 0x41; // 'A'
  }

  Future<bool> eraseStorage() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x45])) return false; // 'E'
    final data = await _serial.readBytes(1, timeoutMs: 5000);
    return data != null && data[0] == 0x41; // 'A'
  }

  Future<FlightStats?> getFlightStats() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x46])) return null; // 'F'
    // 24 bytes: flight_time_ms(3) max_accel_mg(2) min_raw_press(4)
    //           time_burnout_ms(3) time_apogee_ms(3) time_recovery_ms(3)
    //           ground_raw_press(3) ground_raw_temp(3)
    final data = await _serial.readBytes(24, timeoutMs: 2000);
    if (data == null) return null;

    var offset = 0;

    int readU24() {
      final v = data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16);
      offset += 3;
      return v;
    }

    int readU16() {
      final v = data[offset] | (data[offset + 1] << 8);
      offset += 2;
      return v;
    }

    int readU32() {
      final v = data[offset] |
          (data[offset + 1] << 8) |
          (data[offset + 2] << 16) |
          (data[offset + 3] << 24);
      offset += 4;
      return v;
    }

    return FlightStats(
      flightTimeMs:   readU24(),
      maxAccelMg:     readU16(),
      minRawPress:    readU32(),
      timeBurnoutMs:  readU24(),
      timeApogeeMs:   readU24(),
      timeRecoveryMs: readU24(),
      groundRawPress: readU24(),
      groundRawTemp:  readU24(),
    );
  }

  Future<FlightData?> downloadFlight({void Function(double progress)? onProgress}) async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x44])) return null; // 'D'

    // 14-byte metadata: uint16 x4 LE + uint24 LE ground_raw_press + uint24 LE ground_raw_temp
    final meta = await _serial.readBytes(14, timeoutMs: 3000);
    if (meta == null) return null;

    final fastPeriodMs   = meta[0] | (meta[1] << 8);
    final slowPeriodMs   = meta[2] | (meta[3] << 8);
    final fastCount      = meta[4] | (meta[5] << 8);
    final totalCount     = meta[6] | (meta[7] << 8);
    final groundRawPress = meta[8]  | (meta[9]  << 8) | (meta[10] << 16);
    final groundRawTemp  = meta[11] | (meta[12] << 8) | (meta[13] << 16);

    final metadata = FlightMetadata(
      fastPeriodMs: fastPeriodMs,
      slowPeriodMs: slowPeriodMs,
      fastCount: fastCount,
      totalCount: totalCount,
      groundRawPress: groundRawPress,
      groundRawTemp: groundRawTemp,
    );

    if (totalCount == 0) {
      return FlightData(metadata: metadata, samples: []);
    }

    // At 9600 baud (~960 B/s): budget 2× theoretical time + 10s overhead.
    final totalBytes = totalCount * 18;
    final timeoutMs = (totalBytes * 2 + 10000).clamp(10000, 300000);

    final raw = await _serial.readBytes(totalBytes, timeoutMs: timeoutMs);
    if (raw == null) return null;

    final samples = <FlightSample>[];
    for (var i = 0; i < totalCount; i++) {
      final b = i * 18;
      final rawPress = raw[b] | (raw[b + 1] << 8) | (raw[b + 2] << 16);
      final ax = _s16(raw[b + 3] | (raw[b + 4] << 8));
      final ay = _s16(raw[b + 5] | (raw[b + 6] << 8));
      final az = _s16(raw[b + 7] | (raw[b + 8] << 8));
      final gx = _s16(raw[b + 9] | (raw[b + 10] << 8));
      final gy = _s16(raw[b + 11] | (raw[b + 12] << 8));
      final gz = _s16(raw[b + 13] | (raw[b + 14] << 8));
      final rawTemp = raw[b + 15] | (raw[b + 16] << 8) | (raw[b + 17] << 16);

      final timeMs = i < fastCount
          ? i * fastPeriodMs
          : fastCount * fastPeriodMs + (i - fastCount) * slowPeriodMs;

      samples.add(FlightSample(
        timeMs: timeMs,
        rawPress: rawPress,
        accelX: ax,
        accelY: ay,
        accelZ: az,
        gyroX: gx,
        gyroY: gy,
        gyroZ: gz,
        rawTemp: rawTemp,
      ));

      if (onProgress != null && i % 100 == 0) {
        onProgress(i / totalCount);
      }
    }

    return FlightData(metadata: metadata, samples: samples);
  }

  Future<int?> getProductType() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x49])) return null; // 'I'
    final data = await _serial.readBytes(1, timeoutMs: 2000);
    if (data == null) return null;
    return data[0]; // 1=LITE, 2=STANDARD
  }

  Future<Bmp384Calib?> getCalibration() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x4B])) return null; // 'K'
    final data = await _serial.readBytes(21, timeoutMs: 2000);
    if (data == null) return null;
    return Bmp384Calib.fromBytes(data);
  }

  Future<LiveSample?> getLiveSample() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x4C])) return null; // 'L'
    // Firmware sends 18 bytes: pressure(3) + accel(6) + gyro(6) + raw_temp(3), all LE.
    final data = await _serial.readBytes(18, timeoutMs: 300);
    if (data == null) return null;
    return LiveSample(
      rawPress: data[0] | (data[1] << 8) | (data[2] << 16),
      accelX:  _s16(data[3]  | (data[4]  << 8)),
      accelY:  _s16(data[5]  | (data[6]  << 8)),
      accelZ:  _s16(data[7]  | (data[8]  << 8)),
      gyroX:   _s16(data[9]  | (data[10] << 8)),
      gyroY:   _s16(data[11] | (data[12] << 8)),
      gyroZ:   _s16(data[13] | (data[14] << 8)),
      rawTemp: data[15] | (data[16] << 8) | (data[17] << 16),
    );
  }

  static int _s16(int v) => v >= 0x8000 ? v - 0x10000 : v;
}
