import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/sim_card.dart';
import '../hud/hud_theme.dart';

/// Full-screen "出示号码" mode: the number in large type plus a QR code of
/// it, for reading out at a counter or letting someone scan it. Tap anywhere
/// or go back to leave.
class ShowNumberPage extends StatelessWidget {
  const ShowNumberPage({super.key, required this.card});

  final SimCard card;

  /// QR payload: the dialable number (digits and a leading +).
  static String qrData(String phone) {
    final t = phone.trim();
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return t.startsWith('+') ? '+$digits' : digits;
  }

  @override
  Widget build(BuildContext context) {
    final number = card.phoneNumber.isEmpty ? '未录入号码' : card.phoneNumber;
    final data = qrData(card.phoneNumber);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: GestureDetector(
          key: const Key('show-number-exit'),
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${card.countryCode} · ${card.carrierName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(number,
                        key: const Key('show-number-text'),
                        style: Hud.mono.copyWith(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            color: Colors.black)),
                  ),
                  const SizedBox(height: 24),
                  if (data.isNotEmpty)
                    Semantics(
                      label: '号码二维码',
                      child: QrImageView(
                        key: const Key('show-number-qr'),
                        data: data,
                        size: 240,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text('点任意处或返回退出',
                      style: TextStyle(color: Color(0xFF64748B))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
