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

  /// Errors for the records quarantined by the last [load].
  List<String> lastLoadErrors = const [];

  Future<List<SimCard>> load() async {
    final prefs = await SharedPreferences.getInstance();
    lastLoadErrors = const [];
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        return await _validated(prefs, raw);
      } on Object {
        // Corrupt payload: fall through to legacy / seed data.
      }
    }
    final legacy = prefs.getString(legacyKey);
    if (legacy != null) {
      try {
        final migrated = await _validated(prefs, legacy);
        await save(migrated);
        return migrated;
      } on Object {
        // Ignore unreadable legacy data.
      }
    }
    if (prefs.getBool(seededKey) ?? false) return [];
    final seeded = buildSeedCards(DateTime.now());
    await save(seeded);
    await prefs.setBool(seededKey, true);
    return seeded;
  }

  Future<List<SimCard>> _validated(SharedPreferences prefs, String raw) async {
    final result = SimCard.decodeListPartial(raw);
    if (result.rejected.isEmpty) return result.cards;
    final previous = prefs.getString(rejectedKey);
    final quarantine = [
      if (previous != null) ...(jsonDecode(previous) as List),
      ...result.rejected,
    ];
    await prefs.setString(rejectedKey, jsonEncode(quarantine));
    await save(result.cards);
    lastLoadErrors = result.errors;
    return result.cards;
  }

  Future<void> save(List<SimCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, SimCard.encodeList(cards));
  }
}
