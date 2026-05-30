import 'package:shared_preferences/shared_preferences.dart';

enum GalleryViewMode { justified, masonry, square, list }

class GallerySettings {
  GalleryViewMode viewMode;
  double justifiedRowHeight; // target row height in justified mode (px) — used as MAX when autoResizeRowHeight=true, used as FIXED when false
  bool autoResizeRowHeight;  // s329 Feature 6: when true, row height scales with viewport width (justified mode); when false, justifiedRowHeight is used as-is
  int masonryColumns; // 2 or 3
  bool groupByDate;
  bool showDateHeaders;
  bool showDateScrubbar;
  bool localTileCacheEnabled;
  int localTileCacheMaxItems;
  int localTileCacheMaxBytes;
  int thumbnailMemoryCacheMb;
  int thumbnailMemoryCacheItems;

  GallerySettings({
    this.viewMode = GalleryViewMode.justified,
    this.justifiedRowHeight = 200,
    this.autoResizeRowHeight = true, // s329 Feature 6: default ON — empirically observed user-reported "tiles jump on resize" when off
    this.masonryColumns = 3,
    this.groupByDate = true,
    this.showDateHeaders = true,
    this.showDateScrubbar = true,
    this.localTileCacheEnabled = true,
    this.localTileCacheMaxItems = 5000,
    this.localTileCacheMaxBytes = 8 * 1024 * 1024,
    this.thumbnailMemoryCacheMb = 128,
    this.thumbnailMemoryCacheItems = 1000,
  });

  // Bounds for the justifiedRowHeight slider — used by both the AppBar sheet and Settings → Files View tile.
  // s329 Feature 6: lower bound 20px (was 120) per user request "min. 20px"; upper bound 400px (was 320)
  // to allow large-tile preference on hi-DPI/wide monitors.
  static const double minRowHeight = 20;
  static const double maxRowHeight = 400;
  // Used by autoResize=true: target row height = viewport_width / tilesPerRowTarget, clamped to [minRowHeight, maxRowHeight].
  // 5 was chosen empirically — produces ~3 tiles at narrow viewport (600px), ~6 at wide (2000px), keeps thumbnails legible.
  static const double tilesPerRowTarget = 5;

  static const _kViewMode = 'gallery_view_mode';
  static const _kRowHeight = 'gallery_row_height';
  static const _kAutoResize = 'gallery_auto_resize_row_height'; // s329 Feature 6
  static const _kMasonryCols = 'gallery_masonry_cols';
  static const _kGroupByDate = 'gallery_group_by_date';
  static const _kShowHeaders = 'gallery_show_date_headers';
  static const _kShowScrubbar = 'gallery_show_date_scrubbar';
  static const _kLocalTileCacheEnabled = 'gallery_local_tile_cache_enabled';
  static const _kLocalTileCacheMaxItems = 'gallery_local_tile_cache_max_items';
  static const _kLocalTileCacheMaxBytes = 'gallery_local_tile_cache_max_bytes';
  static const _kThumbnailMemoryCacheMb = 'gallery_thumbnail_memory_cache_mb';
  static const _kThumbnailMemoryCacheItems =
      'gallery_thumbnail_memory_cache_items';

  static Future<GallerySettings> load() async {
    final p = await SharedPreferences.getInstance();
    return GallerySettings(
      viewMode: GalleryViewMode.values[p.getInt(_kViewMode) ?? 0],
      justifiedRowHeight: p.getDouble(_kRowHeight) ?? 200,
      autoResizeRowHeight: p.getBool(_kAutoResize) ?? true,
      masonryColumns: p.getInt(_kMasonryCols) ?? 3,
      groupByDate: p.getBool(_kGroupByDate) ?? true,
      showDateHeaders: p.getBool(_kShowHeaders) ?? true,
      showDateScrubbar: p.getBool(_kShowScrubbar) ?? true,
      localTileCacheEnabled: p.getBool(_kLocalTileCacheEnabled) ?? true,
      localTileCacheMaxItems: p.getInt(_kLocalTileCacheMaxItems) ?? 5000,
      localTileCacheMaxBytes:
          p.getInt(_kLocalTileCacheMaxBytes) ?? 8 * 1024 * 1024,
      thumbnailMemoryCacheMb: p.getInt(_kThumbnailMemoryCacheMb) ?? 128,
      thumbnailMemoryCacheItems: p.getInt(_kThumbnailMemoryCacheItems) ?? 1000,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt(_kViewMode, viewMode.index),
      p.setDouble(_kRowHeight, justifiedRowHeight),
      p.setBool(_kAutoResize, autoResizeRowHeight),
      p.setInt(_kMasonryCols, masonryColumns),
      p.setBool(_kGroupByDate, groupByDate),
      p.setBool(_kShowHeaders, showDateHeaders),
      p.setBool(_kShowScrubbar, showDateScrubbar),
      p.setBool(_kLocalTileCacheEnabled, localTileCacheEnabled),
      p.setInt(_kLocalTileCacheMaxItems, localTileCacheMaxItems),
      p.setInt(_kLocalTileCacheMaxBytes, localTileCacheMaxBytes),
      p.setInt(_kThumbnailMemoryCacheMb, thumbnailMemoryCacheMb),
      p.setInt(_kThumbnailMemoryCacheItems, thumbnailMemoryCacheItems),
    ]);
  }

  // s329 Feature 6: compute the effective row height to feed JustifiedGrid given the current
  // viewport width. When autoResize is OFF, returns the user-set fixed value. When ON, scales
  // proportionally to viewport — eliminates the "tiles jump back to original size when last
  // photo wraps to next row" symptom user reported. Bounded by [minRowHeight, maxRowHeight].
  double effectiveRowHeight(double viewportWidth) {
    if (!autoResizeRowHeight) {
      return justifiedRowHeight.clamp(minRowHeight, maxRowHeight);
    }
    final target = viewportWidth / tilesPerRowTarget;
    return target.clamp(minRowHeight, maxRowHeight);
  }
}
