import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:logger/logger.dart';
import '../../../core/network/relay_client.dart';

class StorageVisualizer extends StatefulWidget {
  final RelayClient relay;
  const StorageVisualizer({super.key, required this.relay});

  @override
  State<StorageVisualizer> createState() => _StorageVisualizerState();
}

class _StorageVisualizerState extends State<StorageVisualizer> {
  final _log = Logger();
  bool _loading = true;
  List<Map<String, dynamic>> _mappingData = [];
  List<Map<String, dynamic>> _providers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      _log.i('Visualizer: Loading providers...');
      final providers = await widget.relay.getProviders();
      _log.i('Visualizer: Loaded ${providers.length} providers.');
      // Set providers immediately so accounts chart always renders
      if (mounted) setState(() { _providers = providers; });

      _log.i('Visualizer: Loading files...');
      final files = await widget.relay.listFiles();
      _log.i('Visualizer: Loaded ${files.length} files.');

      final List<Map<String, dynamic>> data = [];
      for (var f in files.take(10)) {
        _log.d('Visualizer: Fetching map for ${f['file_id']}...');
        try {
          final map = await widget.relay.getFileMap(f['file_id']);
          for (var chunk in map['chunks'] ?? []) {
            for (var shard in chunk['shards'] ?? []) {
              final location = shard['location'] as String;  // full: "gdrive:email@gmail.com"
              data.add({'file': f['name'], 'location': location, 'size': (shard['size'] as num).toDouble()});
            }
          }
        } catch (mapErr) {
          _log.w('Visualizer: skip map for ${f['file_id']}: $mapErr'); // non-fatal
        }
      }
      if (mounted) setState(() { _mappingData = data; _loading = false; });
      _log.i('Visualizer: Load complete.');
    } catch (e, s) {
      _log.e('Visualizer ERROR', error: e, stackTrace: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load visualizer: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Storage Visualizer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Storage Quota distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _providers.isEmpty 
              ? const Center(child: Text('No accounts found. Refresh to retry.'))
              : PieChart(
                  PieChartData(
                    sections: _providers.map((p) {
                      final used = (p['quota_used_gb'] as num?)?.toDouble() ?? 0.1;
                      final email = (p['email'] as String?) ?? (p['type'] as String? ?? 'unknown');
                      final label = email.contains('@') ? email.split('@').first : email;
                      return PieChartSectionData(
                        value: used,
                        title: '$label\n${used.toStringAsFixed(1)}GB',
                        radius: 60,
                        color: Colors.primaries[_providers.indexOf(p) % Colors.primaries.length],
                        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      );
                    }).toList(),
                  ),
                ),
          ),
          const SizedBox(height: 32),
          const Text('Data mapping (Bytes per Provider)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (_mappingData.isNotEmpty)
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  barGroups: _buildBarGroups(),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          final keys = _providerLabels.keys.toList();
                          if (idx < 0 || idx >= keys.length) return const Text('');
                          final label = keys[idx];
                          final short = label.contains('@') ? label.split('@').first : label;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(short, style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_mappingData.isEmpty) 
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32), 
                child: Text('No file mapping data available. Please refresh or upload files.')
              )
            ),
        ],
      ),
    );
  }

  // Maps account email → total shard bytes; used by bar chart and labels
  // location format from Relay: "gdrive:email@gmail.com" → split on ':' to get email
  Map<String, double> get _providerLabels {
    final map = <String, double>{};
    for (var p in _providers) {
      final key = (p['email'] as String?) ?? (p['id'] as String?) ?? (p['type'] as String? ?? 'unknown');
      map[key] = 0;
    }
    for (var d in _mappingData) {
      final loc = d['location'] as String? ?? '';
      final email = loc.contains(':') ? loc.split(':').last : loc;
      map[email] = (map[email] ?? 0) + (d['size'] as double);
    }
    return map;
  }

  List<BarChartGroupData> _buildBarGroups() {
    final sizes = _providerLabels;
    final List<BarChartGroupData> groups = [];
    int i = 0;
    sizes.forEach((_, size) {
      groups.add(BarChartGroupData(
        x: i++,
        barRods: [
          BarChartRodData(
            toY: size / (1024 * 1024), // MB
            color: Colors.blueAccent,
            width: 20,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ));
    });
    return groups;
  }
}
