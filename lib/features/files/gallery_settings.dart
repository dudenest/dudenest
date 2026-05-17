import 'package:shared_preferences/shared_preferences.dart';

enum GalleryViewMode { justified, masonry, square, list }

class GallerySettings {
  GalleryViewMode viewMode;
  double justifiedRowHeight; // target row height in justified mode (px)
  int masonryColumns;        // 2 or 3
  bool groupByDate;
  bool showDateHeaders;
  bool showDateScrubbar;

  GallerySettings({
    this.viewMode = GalleryViewMode.justified,
    this.justifiedRowHeight = 200,
    this.masonryColumns = 3,
    this.groupByDate = true,
    this.showDateHeaders = true,
    this.showDateScrubbar = true,
  });

  static const _kViewMode = 'gallery_view_mode';
  static const _kRowHeight = 'gallery_row_height';
  static const _kMasonryCols = 'gallery_masonry_cols';
  static const _kGroupByDate = 'gallery_group_by_date';
  static const _kShowHeaders = 'gallery_show_date_headers';
  static const _kShowScrubbar = 'gallery_show_date_scrubbar';

  static Future<GallerySettings> load() async {
    final p = await SharedPreferences.getInstance();
    return GallerySettings(
      viewMode: GalleryViewMode.values[p.getInt(_kViewMode) ?? 0],
      justifiedRowHeight: p.getDouble(_kRowHeight) ?? 200,
      masonryColumns: p.getInt(_kMasonryCols) ?? 3,
      groupByDate: p.getBool(_kGroupByDate) ?? true,
      showDateHeaders: p.getBool(_kShowHeaders) ?? true,
      showDateScrubbar: p.getBool(_kShowScrubbar) ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt(_kViewMode, viewMode.index),
      p.setDouble(_kRowHeight, justifiedRowHeight),
      p.setInt(_kMasonryCols, masonryColumns),
      p.setBool(_kGroupByDate, groupByDate),
      p.setBool(_kShowHeaders, showDateHeaders),
      p.setBool(_kShowScrubbar, showDateScrubbar),
    ]);
  }
}
