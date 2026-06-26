import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'base_serial_service.dart';

class AndroidSerialService extends BaseSerialService {
  final Map<String, UsbDevice> _devices = {};
  UsbPort? _port;
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<UsbEvent>? _eventSub;
  final _rxBuffer = <int>[];
  bool _connected = false;

  @override
  void Function(bool isTx, List<int> bytes)? onLog;
  @override
  void Function()? onDisconnect;

  @override
  bool get isConnected => _connected;

  @override
  List<String> get availablePorts => _devices.keys.toList();

  @override
  Future<void> refreshPorts() async {
    final list = await UsbSerial.listDevices();
    _devices.clear();
    for (final d in list) {
      _devices[_deviceLabel(d)] = d;
    }
    _eventSub ??= UsbSerial.usbEventStream?.listen(_onUsbEvent);
  }

  String _deviceLabel(UsbDevice d) {
    final name = d.productName ?? 'USB Serial';
    return '$name (${d.deviceName})';
  }

  void _onUsbEvent(UsbEvent event) {
    if (event.event == UsbEvent.ACTION_USB_DETACHED && _connected) {
      _cleanup();
      onDisconnect?.call();
    }
  }

  @override
  Future<bool> connectAsync(String portId) async {
    final device = _devices[portId];
    if (device == null) return false;
    try {
      _port = await device.create();
      if (_port == null) return false;
      final opened = await _port!.open();
      if (!opened) {
        _port = null;
        return false;
      }
      await _port!.setDTR(false);
      await _port!.setRTS(false);
      // Firmware UART runs at 57600 (see uart.c) — kept permanently as of
      // 2026-06-26, not a temporary bring-up rate.
      _port!.setPortParameters(
          57600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      _sub = _port!.inputStream?.listen(
        (data) {
          _rxBuffer.addAll(data);
          onLog?.call(false, data);
        },
        onError: (_) {
          _cleanup();
          onDisconnect?.call();
        },
        onDone: () {
          _cleanup();
          onDisconnect?.call();
        },
      );
      _connected = true;
      return true;
    } catch (_) {
      _port = null;
      return false;
    }
  }

  void _cleanup() {
    _sub?.cancel();
    _sub = null;
    try {
      _port?.close();
    } catch (_) {}
    _port = null;
    _connected = false;
    _rxBuffer.clear();
  }

  @override
  void disconnect() => _cleanup();

  @override
  void flushRx() => _rxBuffer.clear();

  @override
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

  @override
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
