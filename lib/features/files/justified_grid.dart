import 'package:flutter/material.dart';
import '../../core/network/relay_client.dart';
import 'date_group_model.dart';
import 'gallery_settings.dart';

// JustifiedGrid — Google Photos-style layout.
// Arranges photos in rows of equal height, each photo preserving its aspect ratio.
// If aspect ratio unknown, falls back to 1:1 and updates when image dimensions arrive.
class JustifiedGrid extends StatefulWidget {
  final List<DateGroup> groups;
  final GallerySettings settings;
  final RelayClient relay;
  final ScrollController scrollController;
  final Map<String, double> groupOffsets; // filled on build, used by DateScrubbar
  final void Function(String id, String name) onOpen;
  final void Function(String id) onToggleSelect;
  final Set<String> selected;
  final bool selectionMode;
  final bool Function(String name) isImage;
  final bool Function(String name) isVideo;
  final IconData Function(String name) fileIcon;

  const JustifiedGrid({
    super.key,
    required this.groups,
    required this.settings,
    required this.relay,
    required this.scrollController,
    required this.groupOffsets,
    required this.onOpen,
    required this.onToggleSelect,
    required this.selected,
    required this.selectionMode,
    required this.isImage,
    required this.isVideo,
    required this.fileIcon,
  });

  @override
  State<JustifiedGrid> createState() => _JustifiedGridState();
}

class _JustifiedGridState extends State<JustifiedGrid> {
  // Cache of aspect ratios: file_id → width/height. Pre-filled from API, updated when image loads.
  final Map<String, double> _ratios = {};

  double _ratio(Map<String, dynamic> f) {
    final id = f['file_id'] as String? ?? '';
    if (_ratios.containsKey(id)) return _ratios[id]!;
    final w = (f['width'] as num?)?.toDouble() ?? 0;
    final h = (f['height'] as num?)?.toDouble() ?? 0;
    if (w > 0 && h > 0) { _ratios[id] = w / h; return _ratios[id]!; }
    return 1.0; // fallback square
  }

  void _onImageLoaded(String id, ImageInfo info, bool _) {
    final r = info.image.width / info.image.height;
    if ((_ratios[id] ?? 0) != r) setState(() => _ratios[id] = r);
  }

  // Build a single row of files sized to target height.
  Widget _buildRow(List<Map<String, dynamic>> files, double availWidth, double targetH) {
    if (files.isEmpty) return const SizedBox.shrink();
    final ratios = files.map(_ratio).toList();
    final totalRatio = ratios.fold(0.0, (s, r) => s + r);
    final scale = availWidth / (totalRatio * targetH + 2 * (files.length - 1));
    final rowH = (targetH * scale).clamp(80.0, targetH * 1.5);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: files.asMap().entries.map((e) {
        final i = e.key; final f = e.value;
        final id = f['file_id'] as String? ?? '';
        final name = f['name'] as String? ?? id;
        final w = ratios[i] * rowH;
        final isSelected = widget.selected.contains(id);
        return Padding(
          padding: EdgeInsets.only(right: i < files.length - 1 ? 2 : 0),
          child: GestureDetector(
            onTap: () => widget.selectionMode ? widget.onToggleSelect(id) : widget.onOpen(id, name),
            onLongPress: () => widget.onToggleSelect(id),
            child: SizedBox(
              width: w, height: rowH,
              child: Stack(fit: StackFit.expand, children: [
                _buildTile(id, name, rowH),
                if (widget.selectionMode) _buildSelectionOverlay(isSelected),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTile(String id, String name, double h) {
    if (widget.isImage(name)) {
      final img = Image.network(
        '${widget.relay.baseUrl}/files/$id/thumbnail',
        headers: widget.relay.headers,
        fit: BoxFit.cover,
        frameBuilder: (ctx, child, frame, loaded) {
          // Detect real image dims once loaded
          return child;
        },
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFF0D1117),
          child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040))),
        ),
        loadingBuilder: (_, child, p) => p == null ? child
            : Container(color: const Color(0xFF0D1117),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 1))),
      );
      // Listen for image dimensions to update aspect ratio cache
      final stream = NetworkImage('${widget.relay.baseUrl}/files/$id/thumbnail', headers: widget.relay.headers)
          .resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener((info, sync) => _onImageLoaded(id, info, sync)));
      return img;
    }
    return Container(
      color: const Color(0xFF111827),
      child: Center(child: Icon(widget.fileIcon(name), size: 36, color: const Color(0xFF6080A0))),
    );
  }

  Widget _buildSelectionOverlay(bool isSelected) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    color: isSelected ? Colors.black54 : Colors.black26,
    child: isSelected
        ? const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 36))
        : Padding(
            padding: const EdgeInsets.all(5),
            child: Align(
              alignment: Alignment.topRight,
              child: Container(width: 22, height: 22,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 2))),
            ),
          ),
  );

  // Splits files into rows using justified algorithm.
  List<List<Map<String, dynamic>>> _buildRows(List<Map<String, dynamic>> files, double availW, double targetH) {
    final rows = <List<Map<String, dynamic>>>[];
    final current = <Map<String, dynamic>>[];
    double currentRatio = 0;
    for (final f in files) {
      final r = _ratio(f);
      final wouldFitW = (currentRatio + r) * targetH + 2 * (current.length);
      if (current.isNotEmpty && wouldFitW > availW) {
        rows.add(List.from(current)); current.clear(); currentRatio = 0;
      }
      current.add(f); currentRatio += r;
    }
    if (current.isNotEmpty) rows.add(current);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final avail = box.maxWidth - (widget.settings.showDateScrubbar ? 30 : 0);
      final targetH = widget.settings.justifiedRowHeight;
      double scrollPos = 0;

      return CustomScrollView(
        controller: widget.scrollController,
        slivers: widget.groups.expand((group) {
          widget.groupOffsets[group.label] = scrollPos;
          final rows = _buildRows(group.files, avail, targetH);
          final headerH = widget.settings.showDateHeaders ? 40.0 : 0.0;
          final contentH = rows.fold(0.0, (s, r) => s + targetH + 2) + headerH + 8;
          scrollPos += contentH;

          return <Widget>[
            if (widget.settings.showDateHeaders)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                  child: Text(group.label,
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _buildRow(rows[i], avail, targetH),
                  ),
                  childCount: rows.length,
                ),
              ),
            ),
          ];
        }).toList(),
      );
    });
  }
}
