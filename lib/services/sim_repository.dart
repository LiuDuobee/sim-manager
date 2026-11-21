import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sim_card.dart';
import 'seed_cards.dart';

/// Local-first persistence: every mutation is written to SharedPreferences
/// (localStorage on web, registry/AppData JSON on Windows).
class SimRepository {
  static const storageKey = 'simvault_v3_cards';
  static const legacyKey = 'sim_cards';
  static const seededKey = 'simvault_v3_seeded';

  /// Invalid records found by the last [load] (e.g. negative fees) are moved
  /// here verbatim instead of being silently fixed or dropped.
  static const rejectedKey = 'simvault_v3_rejected';

  /// Archived cards (归档区), same encoding as the vault.
  static const archiveKey = 'simvault_v3_archive';

  /// True when the stored archive could not be read; [saveArchive] then
  /// refuses to overwrite it.
  bool _archiveUnreadable = false;

  /// Errors for the records quarantined by the last [load].
  List<String> lastLoadErrors = const [];

  /// Rejected records that still have to reach [rejectedKey]. [save] writes
  /// them first and refuses to touch the vault until that succeeds, so a
  /// failed quarantine can never let a later save drop them.
  List<Object?> _pendingQuarantine = const [];

  Future<List<SimCard>> load() async {
    final prefs = await SharedPreferences.getInstance();
    lastLoadErrors = const [];
    final raw = prefs.getString(storageKey);
    final current = raw == null ? null : _decode(raw);
    if (current != null) return _accept(current);
    final legacy = prefs.getString(legacyKey);
    final migrated = legacy == null ? null : _decode(legacy);
    if (migrated != null) {
      final cards = await _accept(migrated);
      if (migrated.rejected.isEmpty) await _trySave(cards);
      return cards;
    }
    if (prefs.getBool(seededKey) ?? false) return [];
    final seeded = buildSeedCards(DateTime.now());
    await save(seeded);
    await prefs.setBool(seededKey, true);
    return seeded;
  }

  /// Null when the payload itself is unreadable (corrupt JSON / wrong shape).
  static ({List<SimCard> cards, List<Object?> rejected, List<String> errors})?
      _decode(String raw) {
    try {
      return SimCard.decodeListPartial(raw);
    } on FormatException {
      return null;
    }
  }

  Future<List<SimCard>> _accept(
      ({
        List<SimCard> cards,
        List<Object?> rejected,
        List<String> errors
      }) result) async {
    if (result.rejected.isEmpty) return result.cards;
    lastLoadErrors = result.errors;
    _pendingQuarantine = result.rejected;
    await _trySave(result.cards);
    return result.cards;
  }

  /// On failure the stored payload stays untouched; the next [save] retries.
  Future<void> _trySave(List<SimCard> cards) async {
    try {
      await save(cards);
    } on Object {
      // Keep the original vault; nothing was overwritten.
    }
  }

  Future<void> _flushQuarantine(SharedPreferences prefs) async {
    if (_pendingQuarantine.isEmpty) return;
    final previous = prefs.getString(rejectedKey);
    final existing = previous == null ? const [] : jsonDecode(previous);
    if (existing is! List) {
      throw const FormatException('隔离区数据损坏，拒绝覆盖');
    }
    final ok = await prefs.setString(
        rejectedKey, jsonEncode([...existing, ..._pendingQuarantine]));
    if (!ok) throw StateError('隔离区写入失败');
    _pendingQuarantine = const [];
  }

  /// Call after [load]: invalid archived records join the same quarantine.
  Future<List<SimCard>> loadArchive() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(archiveKey);
    if (raw == null) return [];
    final result = _decode(raw);
    if (result == null) {
      _archiveUnreadable = true;
      lastLoadErrors = [...lastLoadErrors, '归档区数据损坏，已保留原始数据'];
      return [];
    }
    if (result.rejected.isNotEmpty) {
      lastLoadErrors = [...lastLoadErrors, ...result.errors];
      _pendingQuarantine = [..._pendingQuarantine, ...result.rejected];
    }
    return result.cards;
  }

  Future<void> saveArchive(List<SimCard> cards) async {
    if (_archiveUnreadable) {
      throw StateError('归档区数据损坏，拒绝覆盖');
    }
    final prefs = await SharedPreferences.getInstance();
    await _flushQuarantine(prefs);
    final ok = await prefs.setString(archiveKey, SimCard.encodeList(cards));
    if (!ok) throw StateError('归档区写入失败');
  }

  Future<void> save(List<SimCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await _flushQuarantine(prefs);
    await prefs.setString(storageKey, SimCard.encodeList(cards));
  }
}
