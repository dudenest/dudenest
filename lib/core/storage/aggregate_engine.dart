import 'dart:typed_data';
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:http/http.dart' as http;
import 'direct_account.dart';
import 'direct_engine.dart';
import 'storage_engine.dart';

/// AggregateEngine — [StorageEngine] łączący WIELE kont direct w jedną galerię (MP1b, multi-konto).
///
/// Trzyma `Map<accountId, StorageEngine>` (zwykle [DirectEngine] per konto Google). `listFiles` merge'uje
/// pliki ze wszystkich kont i taguje każdy plik polem `account_id`. Operacje na pojedynczym pliku
/// (`download/delete/getFileMap/getMeta/patchMeta` + `thumbnail/preview/original`) routują do właściwego
/// silnika po `account_id` pliku — a że interfejs [StorageEngine] przekazuje tym metodom tylko `fileId`
/// (String), routing idzie przez INDEKS `Map<fileId, accountId>` budowany przy `listFiles`. Drive file-id
/// są globalnie unikalne (nie tylko per konto), więc kolizji między kontami nie ma.
///
/// Rdzeń (konstruktor z mapą silników) jest CZYSTY i testowalny bez sieci/OAuth (fake silniki).
/// Budowę z realnych kont robi async fabryka [fromAccounts] (mint tokenów przez [AccountsService]).
class AggregateEngine implements StorageEngine {
  final Map<String, StorageEngine> _engines; // kolejność = priorytet; pierwszy = konto domyślne (upload)
  final Map<String, String> _owner = {}; // file_id → accountId; przebudowywany od zera w listFiles
  /// accountId'y, których `listFiles` padło przy ostatnim odświeżeniu (np. odwołany token). Diagnostyka
  /// — jedno złe konto NIE gasi galerii (partial results); UI może to pokazać. Puste = wszystkie OK.
  final List<String> lastListErrors = [];

  AggregateEngine(Map<String, StorageEngine> engines) : _engines = engines;

  /// Buduje agregat z kont usera: per konto [DirectEngine] z tokenem mintowanym przez [svc].tokenFor
  /// (cache tokenu jest w AccountsService, więc DirectEngine.accessToken() nie bije do backendu per żądanie).
  static Future<AggregateEngine> fromAccounts(AccountsService svc, {http.Client? client}) async {
    final accounts = await svc.list();
    final engines = <String, StorageEngine>{};
    for (final a in accounts) {
      engines[a.accountId] =
          DirectEngine(accessToken: () => svc.tokenFor(a.accountId), client: client);
    }
    return AggregateEngine(engines);
  }

  bool get isEmpty => _engines.isEmpty;
  int get accountCount => _engines.length;

  StorageEngine get _defaultEngine {
    if (_engines.isEmpty) throw StorageException('AggregateEngine: brak podłączonych kont');
    return _engines.values.first;
  }

  String get _defaultAccountId => _engines.keys.first;

  // Routing dla operacji async (delete/download/meta) — nieznany plik to błąd (nie było go w listFiles).
  StorageEngine _routeOrThrow(String fileId) {
    final acc = _owner[fileId];
    final e = acc != null ? _engines[acc] : null;
    if (e == null) {
      throw StorageException('AggregateEngine: nieznane konto dla pliku $fileId', statusCode: 404);
    }
    return e;
  }

  // Routing dla ImageProviderów — wołane synchronicznie z build(), więc NIE może rzucać: nieznany plik
  // (teoretycznie tylko przy stanie przejściowym) → fallback na pierwszy silnik zamiast crashu w UI.
  StorageEngine _routeOrFirst(String fileId) {
    final acc = _owner[fileId];
    return (acc != null ? _engines[acc] : null) ?? _defaultEngine;
  }

  @override
  Future<List<Map<String, dynamic>>> listFiles() async {
    _owner.clear(); // przebuduj indeks od zera — usunięte pliki muszą zniknąć z routingu
    lastListErrors.clear();
    // Per-konto + równolegle: padnięcie JEDNEGO konta (np. odwołany/wygasły token) NIE gasi całej
    // galerii — zbieramy częściowe wyniki i notujemy które konto padło. To sedno multi-konta.
    final results = await Future.wait(_engines.entries.map((e) async {
      try {
        return MapEntry(e.key, await e.value.listFiles());
      } catch (_) {
        lastListErrors.add(e.key);
        return MapEntry(e.key, const <Map<String, dynamic>>[]);
      }
    }));
    // Wszystkie konta padły (a jakieś były) → to realny błąd połączenia: rzuć, żeby ekran pokazał
    // stan błędu/„Reconnect" zamiast pustego grida udającego „brak plików".
    if (_engines.isNotEmpty && lastListErrors.length == _engines.length) {
      throw StorageException(
          'AggregateEngine: wszystkie konta (${_engines.length}) nie odpowiedziały przy listFiles');
    }
    final out = <Map<String, dynamic>>[];
    for (final r in results) {
      for (final f in r.value) {
        f['account_id'] = r.key; // tag konta na mapie pliku (dla UI/routingu)
        final id = f['file_id'] as String?;
        if (id != null && id.isNotEmpty) _owner[id] = r.key;
        out.add(f);
      }
    }
    return out; // konkatenacja per konto (globalne sortowanie chronologiczne = osobny dług, nie regresja)
  }

  @override
  Future<Map<String, dynamic>> fileManifest({String? since}) async =>
      {'files': await listFiles(), 'revision': '', 'unchanged': false};

  @override
  Future<Map<String, dynamic>> uploadFile(String filename, Uint8List bytes,
      {String strategy = 'Replica'}) async {
    // MP1: upload do konta DOMYŚLNEGO (pierwsze). Otaguj wynik account_id + dopisz do indeksu, żeby
    // kolejne operacje (delete/preview) na świeżo wgranym pliku routowały bez ponownego listFiles.
    final res = await _defaultEngine.uploadFile(filename, bytes, strategy: strategy);
    res['account_id'] = _defaultAccountId;
    final id = res['file_id'] as String?;
    if (id != null && id.isNotEmpty) _owner[id] = _defaultAccountId;
    return res;
  }

  @override
  Future<Uint8List> downloadFile(String fileId) => _routeOrThrow(fileId).downloadFile(fileId);

  @override
  Future<void> deleteFile(String fileId) async {
    await _routeOrThrow(fileId).deleteFile(fileId);
    _owner.remove(fileId);
  }

  @override
  Future<Map<String, dynamic>> getFileMap(String fileId) => _routeOrThrow(fileId).getFileMap(fileId);

  @override
  Future<Map<String, dynamic>> getMeta(String fileId) => _routeOrThrow(fileId).getMeta(fileId);

  @override
  Future<Map<String, dynamic>> patchMeta(String fileId, Map<String, dynamic> patch) =>
      _routeOrThrow(fileId).patchMeta(fileId, patch);

  @override
  ImageProvider thumbnail(String fileId) => _routeOrFirst(fileId).thumbnail(fileId);

  @override
  ImageProvider preview(String fileId) => _routeOrFirst(fileId).preview(fileId);

  @override
  ImageProvider original(String fileId) => _routeOrFirst(fileId).original(fileId);
}
