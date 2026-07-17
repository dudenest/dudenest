import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/core/storage/storage_engine.dart';

// Przypina kontrakt E2 (2026-07-17): RelayClient MUSI implementować StorageEngine,
// a fabryki obrazów muszą zwracać dokładnie te same URL-e co dawny Image.network,
// żeby migracja ekranów była bez regresji. Gdy dojdzie DirectEngine (E3), tu wpadnie
// druga bateria testów tego samego interfejsu.
void main() {
  // Compile-time: RelayClient jest StorageEngine (złamanie = błąd kompilacji tu).
  test('RelayClient implements StorageEngine', () {
    final StorageEngine engine = RelayClient('https://relay.dudenest.com');
    expect(engine, isA<RelayClient>());
  });

  group('ImageProvidery zwracają te same URL-e co dawny Image.network', () {
    final r = RelayClient('https://relay.dudenest.com');

    test('thumbnail → /files/{id}/thumbnail', () {
      final img = r.thumbnail('abc123') as NetworkImage;
      expect(img.url, 'https://relay.dudenest.com/files/abc123/thumbnail');
    });

    test('preview → /files/{id}/preview', () {
      final img = r.preview('abc123') as NetworkImage;
      expect(img.url, 'https://relay.dudenest.com/files/abc123/preview');
    });

    test('original → /files/{id}', () {
      final img = r.original('abc123') as NetworkImage;
      expect(img.url, 'https://relay.dudenest.com/files/abc123');
    });
  });
}
