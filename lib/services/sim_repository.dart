import 'package:shared_preferences/shared_preferences.dart';

import '../models/sim_card.dart';
import 'seed_cards.dart';

/// Local-first persistence: every mutation is written to SharedPreferences
/// (localStorage on web, registry/AppData JSON on Windows).
class SimRepository {
  static const storageKey = 'simvault_v3_cards';
  static const legacyKey = 'sim_cards';
  static const seededKey = 'simvault_v3_seeded';

  Future<List<SimCard>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        return SimCard.decodeList(raw);
      } on Object {
        // Corrupt payload: fall through to legacy / seed data.
      }
    }
    final legacy = prefs.getString(legacyKey);
    if (legacy != null) {
      try {
        final migrated = SimCard.decodeList(legacy);
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

  Future<void> save(List<SimCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, SimCard.encodeList(cards));
  }
}
