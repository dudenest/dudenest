import 'dart:js_interop';
import 'package:web/web.dart' as web;
@JS('gtag') external void _gtag(JSAny command, JSAny name, [JSAny? parameters]);
class Analytics {
  static void event(String name, [Map<String, Object?> parameters = const {}]) => _gtag('event'.toJS, name.toJS, parameters.jsify());
  static void pageView(String path, String title) => event('page_view', {
        'page_location': analyticsVirtualLocation(web.window.location.origin, path),
        'page_path': path,
        'page_title': title,
      });
}
String analyticsPathForTab(int tab) => const {0: '/photos', 1: '/files', 3: '/settings'}[tab] ?? '/photos';
String analyticsTitleForTab(int tab) => const {0: 'Photos', 1: 'Files', 3: 'Settings'}[tab] ?? 'Photos';
String analyticsVirtualLocation(String origin, String path) => '$origin$path';
