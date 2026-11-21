import 'dart:convert';

import 'sim_card.dart';

/// What a slot-bearing medium is: the phone's own eSIM, or a rewritable
/// eUICC card (eSTK, 9eSIM, 5ber…) that hosts several profiles.
enum MediumKind { builtinEsim, euicc }

extension MediumKindLabel on MediumKind {
  String get label => switch (this) {
        MediumKind.builtinEsim => '设备内置 eSIM',
        MediumKind.euicc => '可复写 eUICC 卡',
      };

  String get wireName => switch (this) {
        MediumKind.builtinEsim => 'BuiltinEsim',
        MediumKind.euicc => 'Euicc',
      };

  static MediumKind parse(String? raw) => raw?.toLowerCase() == 'builtinesim'
      ? MediumKind.builtinEsim
      : MediumKind.euicc;
}

/// A brand / model preset for a medium. [capacity] is null when the maker
/// publishes no fixed profile count (the user enters it).
class MediumModel {
  const MediumModel({
    required this.id,
    required this.brand,
    required this.model,
    required this.kind,
    this.capacity,
    this.approx = false,
    this.capacityNote = '',
    this.notRecommended = false,
    this.note = '',
  });

  final String id;
  final String brand;
  final String model;
  final MediumKind kind;
  final int? capacity;

  /// The maker quotes "≈ N" (depends on profile size).
  final bool approx;

  /// Shown instead of the bare number, e.g. "约 8–9".
  final String capacityNote;

  /// Still selectable for cards already owned, flagged in the picker.
  final bool notRecommended;
  final String note;

  String get name => model.isEmpty ? brand : '$brand $model';

  String get capacityLabel => capacity == null
      ? '容量自填'
      : capacityNote.isNotEmpty
          ? capacityNote
          : '${approx ? '≈' : ''}$capacity';
}

const builtinEsimDefaultCapacity = 10;

const mediumModels = <MediumModel>[
  MediumModel(
      id: 'estk-c',
      brand: 'eSTK',
      model: 'C',
      kind: MediumKind.euicc,
      capacity: 13,
      approx: true),
  MediumModel(
      id: 'estk-plus',
      brand: 'eSTK',
      model: 'Plus+',
      kind: MediumKind.euicc,
      capacity: 26,
      approx: true),
  MediumModel(
      id: 'estk-max',
      brand: 'eSTK',
      model: 'Max',
      kind: MediumKind.euicc,
      capacity: 60,
      approx: true),
  MediumModel(
      id: '9esim-v0',
      brand: '9eSIM',
      model: 'V0',
      kind: MediumKind.euicc,
      capacity: 15),
  MediumModel(
      id: '9esim-v0max',
      brand: '9eSIM',
      model: 'V0 Max',
      kind: MediumKind.euicc,
      capacity: 30),
  MediumModel(
      id: '9esim-v3',
      brand: '9eSIM',
      model: 'V3',
      kind: MediumKind.euicc,
      capacity: 50),
  MediumModel(
      id: 'xesim-x1',
      brand: 'XeSIM',
      model: 'X1',
      kind: MediumKind.euicc,
      capacity: 15),
  MediumModel(
      id: 'xesim-x2',
      brand: 'XeSIM',
      model: 'X2',
      kind: MediumKind.euicc,
      capacity: 30),
  MediumModel(
      id: 'xesim-x2pro',
      brand: 'XeSIM',
      model: 'X2 Pro',
      kind: MediumKind.euicc,
      capacity: 30),
  MediumModel(
      id: 'beesim-v1',
      brand: 'BeeSIM',
      model: 'V1',
      kind: MediumKind.euicc,
      capacity: 8,
      approx: true,
      capacityNote: '约 8–9'),
  MediumModel(
      id: 'switch-pro',
      brand: 'Switch',
      model: 'Pro',
      kind: MediumKind.euicc,
      capacity: 15),
  MediumModel(
      id: 'switch-max',
      brand: 'Switch',
      model: 'Max',
      kind: MediumKind.euicc,
      capacity: 15),
  MediumModel(
      id: 'switch-ultra',
      brand: 'Switch',
      model: 'Ultra',
      kind: MediumKind.euicc,
      capacity: 50),
  MediumModel(
      id: 'roamhop-lite',
      brand: 'RoamHop',
      model: 'Lite',
      kind: MediumKind.euicc),
  MediumModel(
      id: 'roamhop-plus',
      brand: 'RoamHop',
      model: 'Plus',
      kind: MediumKind.euicc),
  MediumModel(
      id: 'roamhop-max',
      brand: 'RoamHop',
      model: 'Max',
      kind: MediumKind.euicc),
  MediumModel(
      id: 'esim-me', brand: 'eSIM.me', model: '', kind: MediumKind.euicc),
  MediumModel(
      id: 'esimkit', brand: 'eSIMKit', model: '', kind: MediumKind.euicc),
  MediumModel(
      id: '5ber',
      brand: '5ber',
      model: '',
      kind: MediumKind.euicc,
      capacity: 15,
      notRecommended: true,
      note: '厂家云服务已停止，仅登记已有存量，不推荐新购'),
  MediumModel(id: 'blank', brand: '白卡 / 其他', model: '', kind: MediumKind.euicc),
  MediumModel(
      id: 'builtin',
      brand: '手机内置 eSIM',
      model: '',
      kind: MediumKind.builtinEsim,
      capacity: builtinEsimDefaultCapacity,
      note: '容量按机型自填，默认 10'),
];

MediumModel? mediumModelById(String id) {
  for (final m in mediumModels) {
    if (m.id == id) return m;
  }
  return null;
}

const maxMediumCapacity = 200;

/// One slot-bearing medium the user owns (a specific eUICC card or a
/// phone's built-in eSIM). Cards point at it with [SimCard.mediumId].
class Medium {
  const Medium({
    required this.id,
    required this.name,
    required this.kind,
    required this.capacity,
    this.modelId = '',
    this.note = '',
  });

  final String id;
  final String name;
  final MediumKind kind;
  final int capacity;
  final String modelId;
  final String note;

  MediumModel? get model => mediumModelById(modelId);

  Medium copyWith(
          {String? name,
          MediumKind? kind,
          int? capacity,
          String? modelId,
          String? note}) =>
      Medium(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        capacity: capacity ?? this.capacity,
        modelId: modelId ?? this.modelId,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.wireName,
        'capacity': capacity,
        'modelId': modelId,
        'note': note,
      };

  factory Medium.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) throw const FormatException('载体缺少 id');
    final cap = json['capacity'];
    if (cap is! num ||
        cap != cap.roundToDouble() ||
        cap < 1 ||
        cap > maxMediumCapacity) {
      throw const FormatException('载体容量 capacity 必须是 1–$maxMediumCapacity 的整数');
    }
    return Medium(
      id: id,
      name: json['name'] as String? ?? id,
      kind: MediumKindLabel.parse(json['kind'] as String?),
      capacity: cap.toInt(),
      modelId: json['modelId'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }

  static String encodeList(List<Medium> media) =>
      jsonEncode([for (final m in media) m.toJson()]);

  /// Unreadable entries are skipped; an empty or broken list falls back to
  /// the legacy 15-slot eSTK medium.
  static List<Medium> decodeList(Object? raw) {
    final out = <Medium>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        try {
          final m = Medium.fromJson(Map<String, dynamic>.from(e));
          if (!out.any((x) => x.id == m.id)) out.add(m);
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
    }
    return out.isEmpty ? [legacyEstkMedium] : out;
  }
}

/// Every pre-v3.4 programmable card lived on one implicit 15-slot eSTK; old
/// data migrates to this medium with identical slot numbers.
const legacyMediumId = 'estk';
const legacyEstkMedium = Medium(
    id: legacyMediumId, name: 'eSTK', kind: MediumKind.euicc, capacity: 15);

extension CardMedium on SimCard {
  /// The medium the card sits on: its explicit [mediumId], or the legacy
  /// eSTK for programmable cards saved before media existed.
  String? get resolvedMediumId =>
      mediumId ?? (onProgrammableMedium ? legacyMediumId : null);
}
