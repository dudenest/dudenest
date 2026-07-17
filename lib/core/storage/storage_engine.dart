import 'dart:typed_data';
import 'package:flutter/widgets.dart' show ImageProvider;

/// StorageEngine — abstrakcja warstwy przechowywania plików/zdjęć.
///
/// Cel (E2, 2026-07-17): odciąć ekrany galerii/plików od KONKRETNEJ implementacji.
/// Dziś jedyną implementacją jest [RelayClient] (rozmowa z relayem przez HTTP). Docelowo
/// (E3) dojdzie `DirectEngine` — bezpośrednie Google Drive REST z klienta, bez relaya —
/// za tym samym interfejsem, więc ekrany nie muszą się zmieniać.
///
/// Zakres celowo WĄSKI: tylko operacje na plikach + fabryki obrazów. Rzeczy specyficzne
/// dla relaya (OAuth kont cloud, WebSocket, admin/*, remote-hand) zostają w [RelayClient]
/// i NIE należą do tego interfejsu — ekrany zarządzania relayem trzymają `RelayClient`
/// wprost, ekrany galerii/plików trzymają `StorageEngine`.
///
/// Typy zwracane celowo takie same jak w dzisiejszym [RelayClient] (`Map<String,dynamic>`),
/// żeby wprowadzenie interfejsu było ADDYTYWNE i bez regresji. Typowane modele (FileEntry)
/// to osobny, późniejszy refaktor.
abstract class StorageEngine {
  /// GET /files — lista FileMap-ów (uploaded). Klucze wg kontraktu relaya.
  Future<List<Map<String, dynamic>>> listFiles();

  /// Manifest kafelków z delta-sync (`revision`/`unchanged`/`files`). `since` = ostatnia
  /// znana rewizja. Implementacja może nie wspierać delty (zwraca pełną listę).
  Future<Map<String, dynamic>> fileManifest({String? since});

  /// Upload pliku. `strategy` — polityka replikacji (np. "Replica").
  Future<Map<String, dynamic>> uploadFile(String filename, Uint8List bytes,
      {String strategy});

  /// Pobranie pełnych bajtów pliku.
  Future<Uint8List> downloadFile(String fileId);

  /// Usunięcie pliku.
  Future<void> deleteFile(String fileId);

  /// Pełny FileMap (repliki, lokalizacje) — używane przez storage visualizer / debug.
  Future<Map<String, dynamic>> getFileMap(String fileId);

  /// Metadane (ulubione, albumy, lokalizacja, podpis).
  Future<Map<String, dynamic>> getMeta(String fileId);

  /// Aktualizacja metadanych.
  Future<Map<String, dynamic>> patchMeta(
      String fileId, Map<String, dynamic> patch);

  // ── Obrazy jako ImageProvider (NIE goły URL) ──────────────────────────────
  // Kluczowe dla planu bez relaya: RelayEngine zwraca NetworkImage z endpointu relaya,
  // ale DirectEngine (E3) NIE ma HTTP endpointu — musi zwrócić bajty z Google Drive
  // owinięte we własny ImageProvider. Dlatego kontrakt to ImageProvider, nie String.

  /// Miniatura (siatka galerii).
  ImageProvider thumbnail(String fileId);

  /// Podgląd pełnoekranowy (średnia rozdzielczość).
  ImageProvider preview(String fileId);

  /// Oryginał (pełna rozdzielczość).
  ImageProvider original(String fileId);
}
