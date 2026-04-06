import 'package:web/web.dart' as web;

String getLocationHref() => web.window.location.href;
void setLocationHref(String url) { web.window.location.href = url; }
void historyReplaceState(String url) { web.window.history.replaceState(null, '', url); }
