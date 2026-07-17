/// Konfiguracja OAuth Google dla trybu DirectEngine (bez relaya).
///
/// `googleWebClientId` to PUBLICZNY identyfikator klienta web (typ „Web application" w Google Cloud
/// Console, projekt dudenest). NIE jest sekretem — ląduje w bundlu JS aplikacji web. Klient publiczny
/// (PKCE/GIS) nie używa client_secret. Utworzony 2026-07-17, authorized origins: dudenest.com +
/// app.dudenest.com; redirect: /auth.
const googleWebClientId =
    '932297984145-def1hl6jfhkv7tmu4u8o4qhr2k0pjb6v.apps.googleusercontent.com';

/// Scope `drive.file` (decyzja B): tylko pliki utworzone/otwarte przez tę aplikację. Non-sensitive →
/// zero CASA, zero limitu 100 userów.
const driveFileScope = 'https://www.googleapis.com/auth/drive.file';
