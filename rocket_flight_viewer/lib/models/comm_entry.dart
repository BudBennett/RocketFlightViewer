class CommEntry {
  final DateTime time;
  final bool isTx;
  final List<int> bytes;

  CommEntry({required this.isTx, required List<int> bytes})
      : time = DateTime.now(),
        bytes = List.unmodifiable(bytes);

  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  String get ascii => String.fromCharCodes(
      bytes.map((b) => (b >= 32 && b < 127) ? b : 46));
}
