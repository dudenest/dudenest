class Analytics { static void event(String name, [Map<String, Object?> parameters = const {}]) {} static void pageView(String path, String title) {} }
String analyticsPathForTab(int tab) => const {0: '/photos', 1: '/files', 3: '/settings'}[tab] ?? '/photos';
String analyticsTitleForTab(int tab) => const {0: 'Photos', 1: 'Files', 3: 'Settings'}[tab] ?? 'Photos';
String analyticsVirtualLocation(String origin, String path) => '$origin$path';
