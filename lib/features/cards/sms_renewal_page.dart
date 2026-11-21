import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/sim_card.dart';
import '../../services/sms_parser.dart';

/// What the user confirmed on the SMS renewal sheet.
typedef SmsRenewal = ({double? amount, DateTime? deadline});

/// Paste a carrier SMS; amount and validity date are pre-filled from it and
/// nothing is written until the user taps 确认写入.
class SmsRenewalPage extends StatefulWidget {
  const SmsRenewalPage({super.key, required this.card, this.initialText});

  final SimCard card;
  final String? initialText;

  @override
  State<SmsRenewalPage> createState() => _SmsRenewalPageState();
}

class _SmsRenewalPageState extends State<SmsRenewalPage> {
  late final _text = TextEditingController(text: widget.initialText);
  final _amount = TextEditingController();
  DateTime? _deadline;
  ParsedSms _parsed = const ParsedSms();
  String? _amountError;

  @override
  void initState() {
    super.initState();
    if (_text.text.isNotEmpty) _parse();
  }

  @override
  void dispose() {
    _text.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _parse() {
    final p = parseRenewalSms(_text.text);
    setState(() {
      _parsed = p;
      if (p.amount != null) {
        _amount.text = p.amount!.toStringAsFixed(p.amount! % 1 == 0 ? 0 : 2);
      }
      if (p.deadline != null) _deadline = p.deadline;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    _text.text = data.text!;
    _parse();
  }

  void _confirm() {
    final raw = _amount.text.trim();
    double? amount;
    if (raw.isNotEmpty) {
      amount = double.tryParse(raw);
      final error = amount == null || !amount.isFinite
          ? '请输入数字'
          : feeError(amount, '充值金额');
      if (error != null) {
        setState(() => _amountError = error);
        return;
      }
    }
    Navigator.pop<SmsRenewal>(context, (amount: amount, deadline: _deadline));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final fmt = DateFormat('yyyy-MM-dd');
    final currencyMismatch =
        _parsed.currency != null && _parsed.currency != c.currency;
    return Scaffold(
      appBar: AppBar(title: Text('短信录入续期 · ${c.carrierName}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          key: const Key('sms-text'),
          controller: _text,
          minLines: 3,
          maxLines: 8,
          onChanged: (_) => _parse(),
          decoration: const InputDecoration(
              labelText: '粘贴运营商短信',
              hintText: '例：充值成功，金额 100.00 元，有效期至 2027年06月30日',
              border: OutlineInputBorder()),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              key: const Key('sms-paste'),
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('从剪贴板粘贴')),
        ),
        const SizedBox(height: 8),
        Text(
            _parsed.isEmpty
                ? '未识别到充值信息，可直接手动填写'
                : [
                    _parsed.success ? '✓ 识别到充值成功' : '未见「充值成功」字样',
                    if (_parsed.amount != null)
                      '金额 ${_parsed.currency ?? ''} ${_parsed.amount}',
                    if (_parsed.deadline != null)
                      '到期 ${fmt.format(_parsed.deadline!)}',
                  ].join(' · '),
            key: const Key('sms-parsed')),
        const SizedBox(height: 16),
        TextField(
          key: const Key('sms-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: '充值金额 (${c.currency})',
              errorText: _amountError,
              helperText: currencyMismatch
                  ? '短信币种是 ${_parsed.currency}，按卡片币种 ${c.currency} 记账，请核对'
                  : null,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        ListTile(
          key: const Key('sms-deadline'),
          contentPadding: EdgeInsets.zero,
          title: const Text('新到期日'),
          subtitle: Text(_deadline == null
              ? '短信未给出，按「${c.renewalBasis.label}」规则自动计算'
              : fmt.format(_deadline!)),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final picked = await showDatePicker(
                context: context,
                initialDate: _deadline ?? c.nextDeadlineDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100));
            if (picked != null) setState(() => _deadline = dateOnly(picked));
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
            key: const Key('sms-confirm'),
            onPressed: _confirm,
            child: const Text('确认写入')),
      ]),
    );
  }
}
