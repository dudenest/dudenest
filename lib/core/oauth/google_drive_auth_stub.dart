// Nie-web (mobile/desktop): DirectEngine OAuth idzie inną drogą (google_sign_in /
// flutter_appauth — zakres E1/mobile). Ten stub istnieje, by kod się kompilował na
// wszystkich platformach; wywołanie poza web jawnie rzuca (nie „po cichu psuje").
Future<String> getDriveAccessToken() async {
  throw UnsupportedError(
      'getDriveAccessToken: DirectEngine OAuth przez GIS działa tylko na web. '
      'Mobile użyje google_sign_in/flutter_appauth (E1).');
}
