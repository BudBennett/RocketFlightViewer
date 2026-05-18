import 'dart:typed_data';

abstract class BaseSerialService {
  void Function(bool isTx, List<int> bytes)? get onLog;
  set onLog(void Function(bool isTx, List<int> bytes)? v);

  void Function()? get onDisconnect;
  set onDisconnect(void Function()? v);

  bool get isConnected;
  List<String> get availablePorts;

  Future<void> refreshPorts() async {}

  Future<bool> connectAsync(String portId);
  void disconnect();
  void flushRx();
  bool sendBytes(List<int> bytes);
  Future<Uint8List?> readBytes(int count, {int timeoutMs = 3000});
}
