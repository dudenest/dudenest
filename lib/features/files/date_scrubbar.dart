import 'package:flutter/material.dart';
import 'date_group_model.dart';

// DateScrubbar — vertical right-side timeline for fast scrolling, identical to Google Photos.
// Usage: wrap gallery content in Stack, Positioned this overlay on the right.
class DateScrubbar extends StatefulWidget {
  final List<DateGroup> groups;
  final ScrollController scrollController;
  final Map<String, double> groupOffsets; // groupLabel → scroll offset (filled by caller)

  const DateScrubbar({
    super.key,
    required this.groups,
    required this.scrollController,
    required this.groupOffsets,
  });

  @override
  State<DateScrubbar> createState() => _DateScrubbarState();
}

class _DateScrubbarState extends State<DateScrubbar> {
  bool _dragging = false;
  String? _activeLabel;
  OverlayEntry? _tooltip;

  void _scrollToGroup(DateGroup g) {
    final offset = widget.groupOffsets[g.label];
    if (offset == null) return;
    widget.scrollController.animateTo(
      offset.clamp(0.0, widget.scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    setState(() => _activeLabel = g.label);
  }

  void _onDrag(BuildContext ctx, Offset localPos, BoxConstraints box) {
    final fraction = (localPos.dy / box.maxHeight).clamp(0.0, 1.0);
    final idx = (fraction * widget.groups.length).floor().clamp(0, widget.groups.length - 1);
    final g = widget.groups[idx];
    setState(() => _activeLabel = g.label);
    _scrollToGroup(g);
  }

  // Show what years are visible — only unique years for compact display.
  List<_ScrubItem> get _items {
    final items = <_ScrubItem>[];
    String? lastYear;
    for (final g in widget.groups) {
      final year = g.date.year.toString();
      if (year != lastYear) {
        items.add(_ScrubItem(label: year, group: g, isYear: true));
        lastYear = year;
      } else if (widget.groups.length <= 24) {
        // Show months when there are few groups
        items.add(_ScrubItem(label: _shortMonth(g.date.month), group: g, isYear: false));
      }
    }
    return items;
  }

  String _shortMonth(int m) {
    const s = ['J','F','M','A','M','J','J','A','S','O','N','D'];
    return s[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final items = _items;

    return GestureDetector(
      onVerticalDragStart: (_) => setState(() => _dragging = true),
      onVerticalDragEnd: (_) => setState(() { _dragging = false; _activeLabel = null; }),
      onVerticalDragUpdate: (det) {
        LayoutBuilder(builder: (ctx, box) { _onDrag(ctx, det.localPosition, box); return const SizedBox(); });
      },
      onTapDown: (det) {
        // handled via LayoutBuilder in the builder below
      },
      child: LayoutBuilder(builder: (ctx, box) {
        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _dragging = true),
          onVerticalDragEnd: (_) => setState(() { _dragging = false; _activeLabel = null; }),
          onVerticalDragUpdate: (det) => _onDrag(ctx, det.localPosition, box),
          onTapDown: (det) => _onDrag(ctx, det.localPosition, box),
          child: Container(
            width: 28,
            color: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: items.map((item) {
                final isActive = _activeLabel == item.group.label;
                return GestureDetector(
                  onTap: () => _scrollToGroup(item.group),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 28,
                    height: 20,
                    decoration: isActive
                        ? BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          )
                        : null,
                    alignment: Alignment.center,
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: item.isYear ? 10 : 9,
                        fontWeight: item.isYear ? FontWeight.w700 : FontWeight.w400,
                        color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      }),
    );
  }
}

class _ScrubItem {
  final String label;
  final DateGroup group;
  final bool isYear;
  const _ScrubItem({required this.label, required this.group, required this.isYear});
}
