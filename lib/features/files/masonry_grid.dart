import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../core/storage/storage_engine.dart';
import 'account_badge.dart';
import 'date_group_model.dart';
import 'gallery_settings.dart';

// MasonryGrid — Pinterest-style variable-height grid using flutter_staggered_grid_view.
class MasonryGrid extends StatelessWidget {
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
  final bool showAccountBadges;

  const MasonryGrid({
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
    this.showAccountBadges = false,
  });

  double _ratio(Map<String, dynamic> f) {
    final w = (f['width'] as num?)?.toDouble() ?? 0;
    final h = (f['height'] as num?)?.toDouble() ?? 0;
    return (w > 0 && h > 0) ? w / h : 1.0;
  }

  Widget _buildTile(BuildContext ctx, Map<String, dynamic> f) {
    final id = f['file_id'] as String? ?? '';
    final name = f['name'] as String? ?? id;
    final isSelected = selected.contains(id);
    final ratio = _ratio(f);

    return GestureDetector(
      onTap: () => selectionMode ? onToggleSelect(id) : onOpen(id, name),
      onLongPress: () => onToggleSelect(id),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(fit: StackFit.expand, children: [
          (isImage(name) || isVideo(name))
              ? Image(
                  image: relay.thumbnail(id),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF0D1117),
                    child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040))),
                  ),
                  loadingBuilder: (_, child, p) => p == null ? child
                      : Container(color: const Color(0xFF0D1117),
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 1))),
                )
              : Container(
                  color: const Color(0xFF111827),
                  child: Center(child: Icon(fileIcon(name), size: 36, color: const Color(0xFF6080A0))),
                ),
          if (isVideo(name))
            const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 36,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
          if (showAccountBadges) AccountBadge(file: f),
          if (selectionMode) AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: isSelected ? Colors.black54 : Colors.black26,
            child: isSelected
                ? const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 36))
                : Padding(
                    padding: const EdgeInsets.all(5),
                    child: Align(alignment: Alignment.topRight,
                      child: Container(width: 22, height: 22,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                            border: Border.all(color: Colors.white70, width: 2))),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: groups.expand((group) {
        return <Widget>[
          if (settings.showDateHeaders)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                child: Text(group.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: settings.masonryColumns,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childCount: group.files.length,
              itemBuilder: (ctx, i) {
                final f = group.files[i];
                final ratio = _ratio(f);
                return AspectRatio(
                  aspectRatio: ratio,
                  child: _buildTile(ctx, f),
                );
              },
            ),
          ),
        ];
      }).toList(),
    );
  }
}
