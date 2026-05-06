import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bmp384_calib.dart';
import '../models/flight_sample.dart';
import '../models/comm_entry.dart';
import '../models/flight_data.dart';
import '../models/flight_stats.dart';
import '../models/live_sample.dart';
import '../services/serial_service.dart';
import '../services/payload_service.dart';

enum AppStatus { disconnected, connected, busy, error }

class FlightController extends ChangeNotifier {
  final _serial = SerialService();
  late final _payload = PayloadService(_serial);

  final List<CommEntry> commLog = [];

  FlightController() {
    _serial.onLog = (isTx, bytes) {
      if (commLog.length >= 1000) commLog.removeAt(0);
      commLog.add(CommEntry(isTx: isTx, bytes: bytes));
      notifyListeners();
    };
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final tm = p.getString('themeMode') ?? 'dark';
    themeMode = tm == 'light' ? ThemeMode.light : tm == 'system' ? ThemeMode.system : ThemeMode.dark;
    useImperial = p.getBool('useImperial') ?? true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('themeMode', mode == ThemeMode.light ? 'light' : mode == ThemeMode.system ? 'system' : 'dark');
  }

  Future<void> setUnits(bool imperial) async {
    useImperial = imperial;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('useImperial', imperial);
  }

  AppStatus status = AppStatus.disconnected;
  String statusMessage = 'Not connected';
  String? selectedPort;
  FlightData? flightData;
  FlightStats? flightStats;
  int? configThrMg;
  int? configLpfSetting;
  int? configFastMaxS;
  double downloadProgress = 0.0;

  int? productType;         // 1=LITE, 2=STANDARD; null=unknown
  bool get hasStorage => productType == 2 || productType == 3;
  Bmp384Calib? calib;       // null until 'K' command succeeds

  FlightData? historyData;    // loaded from CSV in History tab
  FlightStats? historyStats;  // always null for CSV-loaded flights
  Bmp384Calib? historyCalib;  // calibration embedded in the CSV

  // App settings — persisted via shared_preferences
  ThemeMode themeMode = ThemeMode.dark;
  bool useImperial = true;

  LiveSample? liveSample;
  final List<LivePoint> liveHistory = [];
  DateTime? _liveStartTime;
  bool liveActive = false;
  Timer? _liveTimer;
  bool _livePolling = false;

  bool get isConnected => status != AppStatus.disconnected;
  bool get isBusy => status == AppStatus.busy;
  bool get isError => status == AppStatus.error;
  List<String> get availablePorts => _serial.availablePorts;

  void selectPort(String? port) {
    selectedPort = port;
    notifyListeners();
  }

  void connect() {
    if (selectedPort == null) return;
    if (_serial.connect(selectedPort!)) {
      // Clear all device-specific data so stale values never show on reconnect.
      configThrMg = null;
      configLpfSetting = null;
      configFastMaxS = null;
      productType = null;
      calib = null;
      flightStats = null;
      status = AppStatus.connected;
      statusMessage = 'Connected to $selectedPort';
      _fetchOnConnect();
    } else {
      statusMessage = 'Failed to open $selectedPort';
    }
    notifyListeners();
  }

  Future<void> _fetchOnConnect() async {
    await _fetchProductType();
    await _fetchConfigOnConnect();
    await _fetchCalibration();
  }

  Future<void> _fetchProductType() async {
    final pt = await _payload.getProductType();
    if (pt != null) {
      productType = pt;
      notifyListeners();
    }
  }

  Future<void> _fetchConfigOnConnect() async {
    final val = await _payload.getConfig();
    if (val != null) {
      configThrMg = val.$1;
      configLpfSetting = val.$2;
      configFastMaxS = val.$3;
      notifyListeners();
    } else {
      _error('Read failed — device not responding');
    }
  }

  Future<void> _fetchCalibration() async {
    final c = await _payload.getCalibration();
    if (c != null) {
      calib = c;
      notifyListeners();
    }
  }

  void disconnect() {
    stopLive();
    _serial.disconnect();
    status = AppStatus.disconnected;
    statusMessage = 'Disconnected';
    productType = null;
    configThrMg = null;
    configLpfSetting = null;
    configFastMaxS = null;
    calib = null;
    notifyListeners();
  }

  void startLive() {
    liveActive = true;
    liveHistory.clear();
    _liveStartTime = DateTime.now();
    _pollLive();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollLive());
    notifyListeners();
  }

  void stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    liveActive = false;
    liveSample = null;
    liveHistory.clear();
    _liveStartTime = null;
    notifyListeners();
  }

  Future<void> _pollLive() async {
    if (!isConnected || isBusy || _livePolling) return;
    _livePolling = true;
    final sample = await _payload.getLiveSample();
    _livePolling = false;
    if (sample != null && liveActive) {
      liveSample = sample;
      final t = DateTime.now().difference(_liveStartTime!).inMilliseconds / 1000.0;
      liveHistory.add(LivePoint(timeSec: t, sample: sample));
      if (liveHistory.length > 60) liveHistory.removeAt(0);
      notifyListeners();
    }
  }

  Future<void> downloadFlight() async {
    _busy('Downloading flight data…');
    downloadProgress = 0.0;
    final data = await _payload.downloadFlight(onProgress: (p) {
      downloadProgress = p;
      notifyListeners();
    });
    if (data != null) {
      flightData = data;
      flightStats = FlightStats.fromData(data, calib: calib);
      _done('Downloaded ${data.metadata.totalCount} samples');
    } else {
      _error('Download failed — check connection or no data recorded');
    }
  }

  Future<void> fetchStats() async {
    _busy('Reading flight stats…');
    final stats = await _payload.getFlightStats();
    if (stats != null) {
      flightStats = stats;
      _done('Flight stats loaded');
    } else {
      flightStats = null;
      _error('Stats read failed');
    }
  }

  Future<void> fetchConfig() async {
    _busy('Reading config…');
    final val = await _payload.getConfig();
    if (val != null) {
      configThrMg = val.$1;
      configLpfSetting = val.$2;
      configFastMaxS = val.$3;
      _done('Config loaded');
    } else {
      _error('Config read failed');
    }
  }

  Future<void> setConfig(int thrMg, int lpfSetting, int fastMaxS) async {
    if (liveActive) stopLive();
    await Future.delayed(const Duration(milliseconds: 50));
    _busy('Saving config…');
    final ok = await _payload.setConfig(thrMg, lpfSetting, fastMaxS);
    if (ok) {
      configThrMg = thrMg;
      configLpfSetting = lpfSetting;
      configFastMaxS = fastMaxS;
      _done('Config saved');
    } else {
      _error('Config save failed');
    }
  }

  /// Remaining slow recording capacity in minutes assuming the fast phase runs
  /// to its configured maximum. Returns null if product type or config unknown.
  int? get slowCapacityMinutes {
    final pt = productType;
    final fmax = configFastMaxS;
    if (pt == null || fmax == null) return null;
    final storageBytes = pt == 3 ? 131072 : 65536;
    const sampleBytes = 18;
    const fastHz = 50;
    final fastBytesMax = fmax * fastHz * sampleBytes;
    if (fastBytesMax >= storageBytes) return 0;
    final slowSamples = (storageBytes - fastBytesMax) ~/ sampleBytes;
    return slowSamples ~/ 60;
  }

  Future<void> exportCsv() async {
    final data = flightData;
    if (data == null || data.isEmpty) return;
    _busy('Preparing CSV…');

    final c = calib;
    final sb = StringBuffer();
    sb.writeln('# fast_period_ms=${data.metadata.fastPeriodMs}  slow_period_ms=${data.metadata.slowPeriodMs}  fast_count=${data.metadata.fastCount}  total_count=${data.metadata.totalCount}');
    if (c != null) sb.writeln('# calib=${c.toLine()}');
    sb.writeln('time_s,raw_press,raw_temp,altitude_m,accel_x_mg,accel_y_mg,accel_z_mg,accel_mag_g,gyro_x_dps,gyro_y_dps,gyro_z_dps');
    final groundRawTemp = data.metadata.groundRawTemp != 0
        ? data.metadata.groundRawTemp
        : (data.samples.isNotEmpty ? data.samples.first.rawTemp : 0);
    final groundTLin = (c != null && groundRawTemp != 0) ? c.tLin(groundRawTemp) : 25.0;
    final refAlt = c != null ? Bmp384Calib.altitudeM(c.pressurePa(data.groundRawPress, groundTLin)) : 0.0;

    for (final s in data.samples) {
      final tLin = c != null ? c.tLin(s.rawTemp) : 25.0;
      final altM = c != null
          ? (Bmp384Calib.altitudeM(c.pressurePa(s.rawPress, tLin)) - refAlt).toStringAsFixed(2)
          : '';
      final gx = (s.gyroX * FlightSample.gyroScaleDps).toStringAsFixed(2);
      final gy = (s.gyroY * FlightSample.gyroScaleDps).toStringAsFixed(2);
      final gz = (s.gyroZ * FlightSample.gyroScaleDps).toStringAsFixed(2);
      sb.writeln('${s.timeSec.toStringAsFixed(3)},${s.rawPress},${s.rawTemp},$altM,${s.accelX},${s.accelY},${s.accelZ},${s.accelMagG.toStringAsFixed(4)},$gx,$gy,$gz');
    }

    final path = await FilePicker.saveFile(
      dialogTitle: 'Save flight data',
      fileName: 'flight_data.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (path != null) {
      await File(path).writeAsString(sb.toString());
      _done('CSV saved');
    } else {
      _done('Export cancelled');
    }
  }

  Future<void> importCsv() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open flight CSV',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) { _error('Cannot read file'); return; }

    _busy('Loading CSV…');
    try {
      final lines = await File(path).readAsLines();

      int fastPeriodMs = 20;
      int slowPeriodMs = 1000;
      int fastCount = 0;
      int totalCount = 0;

      Bmp384Calib? parsedCalib;
      for (final line in lines) {
        if (!line.startsWith('#')) break;
        final m1 = RegExp(r'fast_period_ms=(\d+)').firstMatch(line);
        final m2 = RegExp(r'slow_period_ms=(\d+)').firstMatch(line);
        final m3 = RegExp(r'fast_count=(\d+)').firstMatch(line);
        final m4 = RegExp(r'total_count=(\d+)').firstMatch(line);
        if (m1 != null) fastPeriodMs = int.parse(m1.group(1)!);
        if (m2 != null) slowPeriodMs = int.parse(m2.group(1)!);
        if (m3 != null) fastCount = int.parse(m3.group(1)!);
        if (m4 != null) totalCount = int.parse(m4.group(1)!);
        if (line.startsWith('# calib=')) {
          parsedCalib = Bmp384Calib.fromLine(line.substring('# calib='.length));
        }
      }

      final headerIdx = lines.indexWhere((l) => l.startsWith('time_s'));
      if (headerIdx < 0) { _error('Invalid CSV — missing header row'); return; }

      final samples = <FlightSample>[];
      for (int i = headerIdx + 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final p = line.split(',');
        if (p.length < 11) continue;
        final gyroX = (double.parse(p[8]) / FlightSample.gyroScaleDps).round();
        final gyroY = (double.parse(p[9]) / FlightSample.gyroScaleDps).round();
        final gyroZ = (double.parse(p[10]) / FlightSample.gyroScaleDps).round();
        samples.add(FlightSample(
          timeMs: (double.parse(p[0]) * 1000).round(),
          rawPress: int.parse(p[1]),
          rawTemp: p[2].isEmpty ? 0 : int.parse(p[2]),
          altitudeM: p[3].isEmpty ? null : double.tryParse(p[3]),
          accelX: int.parse(p[4]),
          accelY: int.parse(p[5]),
          accelZ: int.parse(p[6]),
          gyroX: gyroX,
          gyroY: gyroY,
          gyroZ: gyroZ,
        ));
      }

      if (samples.isEmpty) { _error('CSV contains no valid samples'); return; }

      historyData = FlightData(
        metadata: FlightMetadata(
          fastPeriodMs: fastPeriodMs,
          slowPeriodMs: slowPeriodMs,
          fastCount: fastCount,
          totalCount: totalCount != 0 ? totalCount : samples.length,
        ),
        samples: samples,
      );
      historyCalib = parsedCalib;
      historyStats = FlightStats.fromData(historyData!);
      _done('Loaded ${samples.length} samples from CSV');
    } catch (e) {
      _error('CSV parse error: $e');
    }
  }

  Future<void> eraseStorage() async {
    _busy('Erasing storage…');
    final ok = await _payload.eraseStorage();
    if (ok) {
      flightData = null;
      _done('Storage erased');
    } else {
      _error('Erase failed');
    }
  }

  void _busy(String msg) {
    status = AppStatus.busy;
    statusMessage = msg;
    notifyListeners();
  }

  void clearLog() {
    commLog.clear();
    notifyListeners();
  }

  void _done(String msg) {
    status = AppStatus.connected;
    statusMessage = msg;
    notifyListeners();
  }

  void _error(String msg) {
    status = AppStatus.error;
    statusMessage = msg;
    notifyListeners();
  }
}
