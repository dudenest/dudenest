import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/storage/storage_engine.dart';
import 'date_group_model.dart';
import 'gallery_settings.dart';

// JustifiedGrid — Google Photos-style layout.
// Aspect ratios: 1) from API width/height; 2) decoded from LQIP (aspect-preserving tiny JPEG);
// 3) fallback 1:1. Never reads from /thumbnail (which is square-cropped 200x200).
class JustifiedGrid extends StatefulWidget {
  final List<DateGroup> groups;
  final GallerySettings settings;
  final StorageEngine relay;
  final ScrollController scrollController;
  final Map<String, double> groupOffsets;
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
  // Aspect ratio cache: file_id → width/height. Pre-filled from API, refined from LQIP.
  final Map<String, double> _ratios = {};
  final Set<String> _loadingLqip = {}; // prevent duplicate async decodes

  double _ratio(Map<String, dynamic> f) {
    final id = f['file_id'] as String? ?? '';
    if (_ratios.containsKey(id)) return _ratios[id]!;
    // Prefer API-provided dims (most accurate, from .dims sidecar on relay)
    final w = (f['width'] as num?)?.toDouble() ?? 0;
    final h = (f['height'] as num?)?.toDouble() ?? 0;
    if (w > 0 && h > 0) { _ratios[id] = w / h; return _ratios[id]!; }
    // Fallback: decode LQIP — it preserves aspect ratio (not square-cropped like thumbnail)
    final lqip = f['lqip'] as String?;
    if (lqip != null && lqip.isNotEmpty && !_loadingLqip.contains(id)) {
      _loadingLqip.add(id);
      _loadLqipRatio(id, lqip);
    }
    return 1.0; // square fallback until async decode finishes
  }

  Future<void> _loadLqipRatio(String id, String lqip) async {
    try {
      final b64 = lqip.contains(',') ? lqip.split(',').last : lqip;
      final bytes = base64Decode(b64);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final r = frame.image.width / frame.image.height.toDouble();
      frame.image.dispose();
      if (mounted && !_ratios.containsKey(id)) setState(() => _ratios[id] = r);
    } catch (_) {}
  }

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
    final isMedia = widget.isImage(name) || widget.isVideo(name);
    if (isMedia) {
      return Stack(fit: StackFit.expand, children: [
        Image(
          image: widget.relay.thumbnail(id),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF0D1117),
            child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040))),
          ),
          loadingBuilder: (_, child, p) => p == null ? child
              : Container(color: const Color(0xFF0D1117),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 1))),
        ),
        if (widget.isVideo(name))
          const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 36,
              shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
      ]);
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
      // s329 Feature 6: when autoResize=true, scale target row height proportionally to viewport.
      // This eliminates the "tile jump-back" symptom — previously when the last photo in a group
      // wrapped to a new row, the remaining tiles in the wider row got more horizontal budget
      // and visually grew back to original size. With viewport-derived targetH, the per-row scale
      // factor is constant across resize because targetH itself shrinks/grows with viewport.
      final targetH = widget.settings.effectiveRowHeight(avail);
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
