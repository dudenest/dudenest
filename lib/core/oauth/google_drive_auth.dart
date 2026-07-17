// Provider access tokenu Google Drive (scope drive.file) dla DirectEngine.
// Conditional export: web → GIS (google_drive_auth_web), nie-web → stub (rzuca).
//
// Użycie: `EngineFactory.build(EngineMode.direct, relay: r, accessToken: getDriveAccessToken)`.
export 'google_drive_auth_stub.dart'
    if (dart.library.js_interop) 'google_drive_auth_web.dart';
