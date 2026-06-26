import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/flight_controller.dart';
import '../widgets/flight_chart.dart';
import '../widgets/live_widget.dart';
import '../widgets/stats_widget.dart';
import '../widgets/monitor_widget.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

Future<void> _saveFlightData(BuildContext context, FlightController ctrl) async {
  final fileName = ctrl.defaultExportFileName;
  ctrl.exportCsv(fileName);
}

String _saveFlightDataLabel(FlightController ctrl) {
  final slot = ctrl.flightData?.metadata.slotIndex;
  return slot != null ? 'Save Flight${slot + 1} Data' : 'Save Flight Data';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _showMonitor = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onHistory = _tabController.index == 2;
    return Consumer<FlightController>(
      builder: (context, ctrl, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Rocket Flight Viewer'),
            actions: [
              if (!Platform.isAndroid)
                IconButton(
                  icon: Icon(
                    Icons.terminal,
                    color: _showMonitor ? Theme.of(context).colorScheme.primary : null,
                  ),
                  tooltip: 'Toggle monitor',
                  onPressed: () => setState(() => _showMonitor = !_showMonitor),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.rocket_launch), text: 'Flight Data'),
                Tab(icon: Icon(Icons.settings), text: 'Settings'),
                Tab(icon: Icon(Icons.history), text: 'History'),
              ],
            ),
          ),
          body: Column(
            children: [
              if (!onHistory) _ConnectionBar(ctrl: ctrl),
              if (!onHistory) _StatusBar(ctrl: ctrl),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _FlightDataTab(ctrl: ctrl),
                    const SettingsScreen(),
                    const HistoryScreen(),
                  ],
                ),
              ),
              if (_showMonitor)
                SizedBox(
                  height: 200,
                  child: MonitorWidget(
                    entries: ctrl.commLog,
                    onClear: ctrl.clearLog,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Flight Data tab
// ---------------------------------------------------------------------------

class _FlightDataTab extends StatefulWidget {
  final FlightController ctrl;

  const _FlightDataTab({required this.ctrl});

  @override
  State<_FlightDataTab> createState() => _FlightDataTabState();
}

class _FlightDataTabState extends State<_FlightDataTab> {
  bool _statsVisible = true;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Column(
      children: [
        if (ctrl.isConnected) _FlightDataActionRow(ctrl: ctrl),
        Expanded(child: _buildContent(context, ctrl)),
      ],
    );
  }

  Widget _buildContent(BuildContext context, FlightController ctrl) {
    if (ctrl.liveActive) {
      return LiveWidget(
        sample: ctrl.liveSample,
        history: ctrl.liveHistory,
        useImperial: ctrl.useImperial,
        baroType: ctrl.baroType,
      );
    }

    if (ctrl.isBusy) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(ctrl.statusMessage, style: const TextStyle(fontSize: 13)),
          if (ctrl.downloadProgress > 0) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: LinearProgressIndicator(value: ctrl.downloadProgress),
            ),
          ],
        ],
      );
    }

    if (ctrl.flightData != null && !ctrl.flightData!.isEmpty) {
      if (Platform.isAndroid) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AndroidSaveRow(ctrl: ctrl),
              if (ctrl.flightStats != null) ...[
                const SizedBox(height: 12),
                StatsWidget(
                  stats: ctrl.flightStats!,
                ),
              ],
            ],
          ),
        );
      }

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.save_alt, size: 16),
                label: Text(_saveFlightDataLabel(ctrl)),
                onPressed: () => _saveFlightData(context, ctrl),
              ),
            ),
          ),
          Expanded(
            child: FlightChart(
              data: ctrl.flightData!,
              useImperial: ctrl.useImperial,
            ),
          ),
          if (ctrl.flightStats != null) ...[
            InkWell(
              onTap: () => setState(() => _statsVisible = !_statsVisible),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _statsVisible ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _statsVisible ? 'Hide Stats' : 'Show Stats',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_statsVisible)
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: StatsWidget(
                  stats: ctrl.flightStats!,
                ),
              ),
          ],
        ],
      );
    }

    return Center(
      child: Text(
        ctrl.isConnected
            ? 'Press Download Data to retrieve flight data'
            : Platform.isAndroid
                ? 'Connect a USB device and tap Connect'
                : 'Select a serial port and connect',
      ),
    );
  }
}

class _FlightDataActionRow extends StatelessWidget {
  final FlightController ctrl;

  const _FlightDataActionRow({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final disableNonLive = ctrl.isBusy || ctrl.liveActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (ctrl.hasStorage) _DownloadButton(ctrl: ctrl, disabled: disableNonLive),
          if (ctrl.hasStorage)
            _ActionButton(
              label: 'Erase',
              icon: Icons.delete_forever,
              busy: disableNonLive,
              danger: true,
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Erase flight data?'),
                    content: Text(ctrl.isPro
                        ? 'This will permanently delete all recorded flights (all 8 slots) on the payload.'
                        : 'This will permanently delete all recorded flight data on the payload.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red),
                        child: const Text('Erase'),
                      ),
                    ],
                  ),
                );
                if (ok == true) ctrl.eraseStorage();
              },
            ),
          _ActionButton(
            label: ctrl.liveActive ? 'Stop Live' : 'Live',
            icon: ctrl.liveActive ? Icons.stop_circle_outlined : Icons.sensors,
            busy: ctrl.isBusy,
            onPressed: () {
              if (ctrl.liveActive) {
                ctrl.stopLive();
              } else {
                ctrl.startLive();
              }
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download button — plain for STANDARD, flight-slot picker menu for PRO
// ---------------------------------------------------------------------------

class _DownloadButton extends StatelessWidget {
  final FlightController ctrl;
  final bool disabled;
  const _DownloadButton({required this.ctrl, required this.disabled});

  @override
  Widget build(BuildContext context) {
    if (!ctrl.isPro) {
      return _ActionButton(
        label: 'Download Data',
        icon: Icons.download,
        busy: disabled,
        onPressed: () => ctrl.downloadFlight(),
      );
    }

    final slots = ctrl.flightSlots;
    final ready = !disabled && slots.length == 8;
    final outline = Theme.of(context).colorScheme.outline;

    return PopupMenuButton<int>(
      enabled: ready,
      tooltip: 'Select flight to download',
      onSelected: (slot) {
        ctrl.selectSlot(slot);
        ctrl.downloadFlight();
      },
      itemBuilder: (context) => List.generate(8, (i) {
        final (valid, total) = slots[i];
        final isNext = i == ctrl.nextSlot;
        final label = valid
            ? 'Flight ${i + 1} ($total samples)${isNext ? ' — next' : ''}'
            : 'Flight ${i + 1} (empty)${isNext ? ' — next' : ''}';
        return PopupMenuItem(value: i, enabled: valid, child: Text(label));
      }),
      child: IgnorePointer(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Download Data'),
          onPressed: () {},
          style: ready ? null : OutlinedButton.styleFrom(foregroundColor: outline.withOpacity(0.38)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection bar
// ---------------------------------------------------------------------------

class _ConnectionBar extends StatefulWidget {
  final FlightController ctrl;
  const _ConnectionBar({required this.ctrl});

  @override
  State<_ConnectionBar> createState() => _ConnectionBarState();
}

class _ConnectionBarState extends State<_ConnectionBar> {
  List<String> _ports = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await widget.ctrl.refreshPorts();
    if (!mounted) return;
    setState(() => _ports = widget.ctrl.availablePorts);
    if (!_ports.contains(widget.ctrl.selectedPort)) {
      widget.ctrl.selectPort(_ports.isNotEmpty ? _ports.first : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: Platform.isAndroid ? 'Scan for USB devices' : 'Refresh port list',
            onPressed: ctrl.isBusy ? null : () => _refresh(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _ports.contains(ctrl.selectedPort) ? ctrl.selectedPort : null,
              hint: Text(Platform.isAndroid ? 'Select USB device' : 'Select port'),
              items: _ports
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: ctrl.isConnected || ctrl.isBusy
                  ? null
                  : (p) => ctrl.selectPort(p),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: ctrl.isBusy
                ? null
                : ctrl.isConnected
                    ? ctrl.disconnect
                    : () => ctrl.connect(),
            style: ElevatedButton.styleFrom(
              backgroundColor: ctrl.isBusy
                  ? null
                  : ctrl.isConnected
                      ? Colors.red[700]
                      : Colors.green[700],
              foregroundColor: ctrl.isBusy ? null : Colors.white,
            ),
            child: Text(ctrl.isConnected ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final FlightController ctrl;
  const _StatusBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: ctrl.isError
          ? Colors.orange.withOpacity(0.35)
          : ctrl.isBusy
              ? cs.secondaryContainer.withOpacity(0.4)
              : ctrl.isConnected
                  ? cs.primaryContainer.withOpacity(0.4)
                  : cs.surfaceContainerHighest.withOpacity(0.4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            ctrl.isError
                ? Icons.cancel
                : ctrl.isBusy
                    ? Icons.hourglass_top
                    : ctrl.isConnected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
            size: 14,
            color: ctrl.isError
                ? Colors.red[400]
                : ctrl.isBusy
                    ? cs.secondary
                    : ctrl.isConnected
                        ? Colors.green[400]
                        : cs.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ctrl.statusMessage,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ctrl.productType != null) ...[
            const SizedBox(width: 8),
            _ProductChip(productType: ctrl.productType!),
          ],
          if (ctrl.batteryVoltage != null) ...[
            const SizedBox(width: 8),
            _BatteryChip(voltage: ctrl.batteryVoltage!),
          ],
        ],
      ),
    );
  }
}

class _ProductChip extends StatelessWidget {
  final int productType;
  const _ProductChip({required this.productType});

  @override
  Widget build(BuildContext context) {
    final label = productType == 2 ? 'STD' : productType == 3 ? 'PRO' : 'v$productType';
    final color = Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _BatteryChip extends StatelessWidget {
  final double voltage;
  const _BatteryChip({required this.voltage});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    if (voltage >= 4.0) {
      icon = Icons.battery_full;
      color = Colors.green[400]!;
    } else if (voltage >= 3.7) {
      icon = Icons.battery_4_bar;
      color = Colors.green[400]!;
    } else if (voltage >= 3.6) {
      icon = Icons.battery_2_bar;
      color = Colors.orange;
    } else {
      icon = Icons.battery_alert;
      color = Colors.red[400]!;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          '${voltage.toStringAsFixed(2)}V',
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared action button
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final bool danger;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: busy ? null : onPressed,
      style: danger
          ? OutlinedButton.styleFrom(foregroundColor: Colors.red)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Android inline filename field + save button
// ---------------------------------------------------------------------------

class _AndroidSaveRow extends StatefulWidget {
  final FlightController ctrl;
  const _AndroidSaveRow({required this.ctrl});

  @override
  State<_AndroidSaveRow> createState() => _AndroidSaveRowState();
}

class _AndroidSaveRowState extends State<_AndroidSaveRow> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final full = widget.ctrl.defaultExportFileName;
    _nameCtrl = TextEditingController(
      text: full.endsWith('.csv') ? full.substring(0, full.length - 4) : full,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              suffixText: '.csv',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.save_alt, size: 16),
          label: const Text('Save'),
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            widget.ctrl.exportCsv('$name.csv');
          },
        ),
      ],
    );
  }
}
