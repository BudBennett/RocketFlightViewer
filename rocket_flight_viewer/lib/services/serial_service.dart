import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialService {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;
  final _rxBuffer = <int>[];

  void Function(bool isTx, List<int> bytes)? onLog;
  void Function()? onDisconnect;

  List<String> get availablePorts => SerialPort.availablePorts;

  bool get isConnected => _port != null && (_port?.isOpen ?? false);

  bool connect(String portName) {
    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        _port = null;
        return false;
      }
      final config = SerialPortConfig();
      config.baudRate = 9600;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.rts = SerialPortRts.off;
      config.dtr = SerialPortDtr.off;
      _port!.config = config;

      _reader = SerialPortReader(_port!);
      _sub = _reader!.stream.listen(
        (data) {
          _rxBuffer.addAll(data);
          onLog?.call(false, data);
        },
        onError: (_) => onDisconnect?.call(),
        onDone:  ()  => onDisconnect?.call(),
      );
      return true;
    } catch (_) {
      _port = null;
      return false;
    }
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _reader?.close();
    _reader = null;
    try {
      _port?.close();
    } catch (_) {}
    _port = null;
    _rxBuffer.clear();
  }

  void flushRx() => _rxBuffer.clear();

  bool sendBytes(List<int> bytes) {
    if (_port == null) return false;
    try {
      _port!.write(Uint8List.fromList(bytes));
      onLog?.call(true, bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> readBytes(int count, {int timeoutMs = 3000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (_rxBuffer.length < count) {
      if (DateTime.now().isAfter(deadline)) return null;
      await Future.delayed(const Duration(milliseconds: 5));
    }
    final result = Uint8List.fromList(_rxBuffer.sublist(0, count));
    _rxBuffer.removeRange(0, count);
    return result;
  }
}
