import 'package:flutter/material.dart';

import '../features/cards/region_flag.dart';
import '../features/hud/hud_theme.dart';
import '../services/region_catalog.dart';

Future<T?> _sheet<T>(
        BuildContext context, Widget Function(BuildContext) body) =>
    showGlassBottomSheet<T>(
      context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: body(context)),
    );

/// Searchable region picker: 中国 with its four regions first, then popular
/// countries, then the rest A–Z; any two-letter code can be used as custom.
Future<RegionInfo?> showRegionPicker(BuildContext context) =>
    _sheet(context, (_) => const _RegionPicker());

class _RegionPicker extends StatefulWidget {
  const _RegionPicker();

  @override
  State<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<_RegionPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Widget _tile(RegionInfo r, {bool indent = false}) => ListTile(
        key: Key('region-${r.code}'),
        contentPadding: EdgeInsets.only(left: indent ? 40 : 16, right: 16),
        leading: FlagText(r.code, size: 22),
        title: Text(r.name),
        trailing: Text('${r.code} · ${r.currency}',
            style: Hud.mono.copyWith(fontSize: 11, color: context.hud.muted)),
        onTap: () => Navigator.pop(context, r),
      );

  Widget _header(String text, {Widget? leading}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          if (leading != null) ...[leading, const SizedBox(width: 10)],
          HudLabel(text),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final hits = searchRegions(_q.text);
    final china = [
      for (final r in hits)
        if (chinaRegions.contains(r)) r
    ];
    final popular = [
      for (final r in hits)
        if (popularRegions.contains(r)) r
    ];
    final others = [
      for (final r in hits)
        if (otherRegions.contains(r)) r
    ];
    final q = _q.text.trim().toUpperCase();
    final custom = RegExp(r'^[A-Z]{2}$').hasMatch(q) &&
        !allRegions.any((r) => r.code == q);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          key: const Key('region-search'),
          controller: _q,
          autofocus: false,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索国家/地区名称或代码，或输入两位代码自定义'),
        ),
      ),
      Expanded(
        child: ListView(children: [
          if (custom)
            ListTile(
              key: const Key('region-custom'),
              leading: FlagText(q, size: 22),
              title: Text('使用自定义代码 $q'),
              onTap: () => Navigator.pop(context, regionFor(q)),
            ),
          if (china.isNotEmpty) ...[
            _header('中国', leading: const FlagText('CN', size: 18)),
            for (final r in china) _tile(r, indent: true),
          ],
          if (popular.isNotEmpty) ...[
            _header('常用'),
            for (final r in popular) _tile(r),
          ],
          if (others.isNotEmpty) ...[
            _header('其他（按代码 A–Z）'),
            for (final r in others) _tile(r),
          ],
        ]),
      ),
    ]);
  }
}

/// Searchable ISO 4217 currency picker (symbol + Chinese name).
Future<CurrencyInfo?> showCurrencyPicker(BuildContext context) =>
    _sheet(context, (_) => const _CurrencyPicker());

class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker();

  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = searchCurrencies(_q.text);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          key: const Key('currency-search'),
          controller: _q,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: '搜索币种代码或中文名'),
        ),
      ),
      Expanded(
        child: ListView(children: [
          for (final c in hits)
            ListTile(
              key: Key('currency-${c.code}'),
              leading: SizedBox(
                width: 48,
                child: Text(c.symbol,
                    style: Hud.mono
                        .copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              title: Text(c.name),
              trailing: Text(c.code, style: Hud.mono),
              onTap: () => Navigator.pop(context, c),
            ),
        ]),
      ),
    ]);
  }
}
