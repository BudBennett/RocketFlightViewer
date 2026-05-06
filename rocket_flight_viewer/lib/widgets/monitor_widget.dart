import 'package:flutter/material.dart';
import '../models/comm_entry.dart';

class MonitorWidget extends StatefulWidget {
  final List<CommEntry> entries;
  final VoidCallback onClear;

  const MonitorWidget({super.key, required this.entries, required this.onClear});

  @override
  State<MonitorWidget> createState() => _MonitorWidgetState();
}

class _MonitorWidgetState extends State<MonitorWidget> {
  final _scroll = ScrollController();
  int _prevCount = 0;

  @override
  void didUpdateWidget(MonitorWidget old) {
    super.didUpdateWidget(old);
    if (widget.entries.length != _prevCount) {
      _prevCount = widget.entries.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF2D2D2D),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              const Text('Monitor',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: widget.onClear,
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white38,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: widget.entries.isEmpty
                ? const Center(
                    child: Text('No communication yet',
                        style: TextStyle(color: Colors.white38, fontSize: 12)))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: widget.entries.length,
                    itemExtent: 18,
                    itemBuilder: (context, i) =>
                        _EntryRow(entry: widget.entries[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  final CommEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = entry.time;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';

    final dirColor = entry.isTx ? const Color(0xFFFFAA44) : const Color(0xFF66CC88);
    const mono = TextStyle(fontFamily: 'Courier New', fontSize: 11);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(timeStr,
              style: mono.copyWith(color: Colors.white38)),
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            child: Text(entry.isTx ? 'TX' : 'RX',
                style: mono.copyWith(
                    color: dirColor, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(entry.hex,
              style: mono.copyWith(color: dirColor)),
          const SizedBox(width: 12),
          Text(entry.ascii,
              style: mono.copyWith(color: dirColor.withOpacity(0.6))),
        ],
      ),
    );
  }
}
