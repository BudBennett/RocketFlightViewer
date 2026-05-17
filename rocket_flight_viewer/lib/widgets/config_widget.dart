import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/flight_controller.dart';

class ConfigWidget extends StatefulWidget {
  final FlightController controller;

  const ConfigWidget({super.key, required this.controller});

  @override
  State<ConfigWidget> createState() => _ConfigWidgetState();
}

const _lpfLabels = [
  '0 — ODR/4  (26 Hz)',
  '1 — ODR/10 (10 Hz)',
  '2 — ODR/20 (5 Hz)',
  '3 — ODR/45 (2.3 Hz)',
  '4 — ODR/100 (1 Hz)',
  '5 — ODR/200 (0.5 Hz)',
  '6 — ODR/400 (0.26 Hz)',
  '7 — ODR/800 (0.13 Hz)',
];

class _ConfigWidgetState extends State<ConfigWidget> {
  final _field = TextEditingController();
  String? _error;
  int _lpfSetting = 1; // default ODR/10

  @override
  void initState() {
    super.initState();
    final v = widget.controller.configThrMg;
    if (v != null) _field.text = v.toString();
    final lpf = widget.controller.configLpfSetting;
    if (lpf != null) _lpfSetting = lpf.clamp(0, 7);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final val = int.tryParse(_field.text.trim());
    if (val == null || val < 100 || val > 32000) {
      setState(() => _error = 'Enter a value between 100 and 32000 mg');
      return;
    }
    setState(() => _error = null);
    widget.controller.setConfig(val, _lpfSetting, widget.controller.configFastMaxS ?? 30, widget.controller.configOdrSel ?? 0x02);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Launch Configuration', style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              const Text(
                'Launch threshold — the acceleration increase above resting level that triggers recording.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _field,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Launch threshold (mg)',
                        suffix: const Text('mg'),
                        errorText: _error,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: widget.controller.isBusy ? null : _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Typical: 2000 mg (2 g) for a small rocket. Range: 100–32000 mg.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('Accel LPF2 corner frequency',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              DropdownButton<int>(
                value: _lpfSetting,
                items: List.generate(8, (i) => DropdownMenuItem(
                  value: i,
                  child: Text(_lpfLabels[i], style: const TextStyle(fontSize: 13)),
                )),
                onChanged: widget.controller.isBusy
                    ? null
                    : (v) { if (v != null) setState(() => _lpfSetting = v); },
              ),
              const Text(
                'Lower frequency = more filtering. Use lower BW for larger/heavier rockets.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
