import 'package:flutter/widgets.dart';

import '../../models/medium.dart';
import '../../models/sim_card.dart';

/// Makes the medium list available to card faces, so a slot tag can read
/// "9eSIM V3 #12" instead of a hard-coded "eSTK".
class MediumScope extends InheritedWidget {
  const MediumScope({super.key, required this.media, required super.child});

  final List<Medium> media;

  static List<Medium> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediumScope>()?.media ??
      const [legacyEstkMedium];

  /// Display name of the medium [card] sits on, or null when it has none.
  static String? nameFor(BuildContext context, SimCard card) {
    final id = card.resolvedMediumId;
    if (id == null) return null;
    for (final m in of(context)) {
      if (m.id == id) return m.name;
    }
    return id == legacyMediumId ? legacyEstkMedium.name : null;
  }

  @override
  bool updateShouldNotify(MediumScope old) => old.media != media;
}
