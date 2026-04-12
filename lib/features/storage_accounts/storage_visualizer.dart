import 'package:flutter/material.dart';
import 'package:graphic/graphic.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/network/relay_client.dart';

class StorageVisualizer extends StatefulWidget {
  final RelayClient relay;
  const StorageVisualizer({super.key, required this.relay});

  @override
  State<StorageVisualizer> createState() => _StorageVisualizerState();
}

class _StorageVisualizerState extends State<StorageVisualizer> {
  bool _loading = true;
  List<Map<String, dynamic>> _sankeyData = [];
  List<Map<String, dynamic>> _providers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final providers = await widget.relay.getProviders();
      final files = await widget.relay.listFiles();
      
      final List<Map<String, dynamic>> data = [];
      
      for (var f in files.take(5)) {
        final map = await widget.relay.getFileMap(f['file_id']);
        final strategy = map['strategy'] ?? 'Chunking';
        
        for (var chunk in map['chunks']) {
          for (var shard in chunk['shards']) {
            final location = shard['location'] as String;
            final providerName = location.split(':').first;
            
            data.add({
              'source': f['name'],
              'destination': providerName,
              'value': shard['size'],
              'type': strategy,
            });
          }
        }
      }

      setState(() {
        _sankeyData = data;
        _providers = providers;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load visualizer: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Storage Quota distribution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: _providers.map((p) {
                  final used = p['quota_used_gb'] as double;
                  final total = p['quota_total_gb'] as double;
                  return PieChartSectionData(
                    value: used,
                    title: '${p['email']}\n${used.toStringAsFixed(1)}GB',
                    radius: 50,
                    color: Colors.primaries[_providers.indexOf(p) % Colors.primaries.length],
                  );
                }).toList(),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Data Mapping (Files to Accounts)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          if (_sankeyData.isNotEmpty)
            SizedBox(
              height: 300,
              child: Chart(
                data: _sankeyData,
                variables: {
                  'source': Variable(accessor: (Map d) => d['source'] as String),
                  'destination': Variable(accessor: (Map d) => d['destination'] as String),
                  'value': Variable(accessor: (Map d) => d['value'] as num),
                },
                elements: [
                  IntervalElement(
                    position: Varset('source') * Varset('value') / Varset('destination'),
                    color: ColorAttr(variable: 'source', values: Defaults.colors10),
                  )
                ],
              ),
            ),
          if (_sankeyData.isEmpty) const Text('No file maps available for visualization'),
        ],
      ),
    );
  }
}
