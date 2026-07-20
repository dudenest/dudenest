// Nie-web (mobile/desktop): DirectEngine OAuth idzie inną drogą (google_sign_in /
// flutter_appauth — zakres E1/mobile). Ten stub istnieje, by kod się kompilował na
// wszystkich platformach; wywołanie poza web jawnie rzuca (nie „po cichu psuje").
Future<String> getDriveAccessToken({bool silent = false, String? hint}) async {
  throw UnsupportedError(
      'getDriveAccessToken: DirectEngine OAuth przez GIS działa tylko na web. '
      'Mobile użyje google_sign_in/flutter_appauth (E1).');
}

// Nie-web: brak trwałego tokenu GIS → nigdy nie auto-łączymy.
Future<bool> hasValidDriveToken() async => false;

// Nie-web: brak trwałego tokenu do wyczyszczenia.
Future<void> clearDriveToken() async {}

// Nie-web: podłączenie przez redirect działa tylko na web.
Future<void> connectDrive() async {
  throw UnsupportedError('connectDrive: tylko web');
}
