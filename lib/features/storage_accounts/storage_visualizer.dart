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
              final location = shard['location'] as String;
              final providerName = location.split(':').first;
              data.add({'file': f['name'], 'provider': providerName, 'size': (shard['size'] as num).toDouble()});
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
                      return PieChartSectionData(
                        value: used,
                        title: '${p['type']}\n${used.toStringAsFixed(1)}GB',
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
                          if (idx < 0 || idx >= _providers.length) return const Text('');
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(_providers[idx]['type'] ?? '?', style: const TextStyle(fontSize: 10)),
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

  List<BarChartGroupData> _buildBarGroups() {
    final Map<String, double> providerSizes = {};
    for (var p in _providers) {
      providerSizes[p['type'] ?? 'unknown'] = 0;
    }
    
    for (var d in _mappingData) {
      final p = d['provider'] as String;
      providerSizes[p] = (providerSizes[p] ?? 0) + (d['size'] as double);
    }

    final List<BarChartGroupData> groups = [];
    int i = 0;
    providerSizes.forEach((provider, size) {
      groups.add(BarChartGroupData(
        x: i++,
        barRods: [
          BarChartRodData(
            toY: size / (1024 * 1024), // Show in MB
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
