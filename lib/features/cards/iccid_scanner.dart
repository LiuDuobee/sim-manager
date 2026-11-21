import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/iccid.dart';

/// Camera scanning exists on Android / iOS / macOS (mobile_scanner); other
/// platforms fall back to typing the ICCID.
bool get iccidScanSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Scans the barcode on a SIM tray / card holder and returns a Luhn-valid
/// ICCID, or null when the user backs out, the camera permission is denied,
/// or scanning isn't available (the caller keeps manual input).
Future<String?> scanIccid(BuildContext context) async {
  if (!iccidScanSupported) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('当前平台不支持相机扫码，请手动输入 ICCID')));
    return null;
  }
  return Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => const IccidScanPage()));
}

class IccidScanPage extends StatefulWidget {
  const IccidScanPage({super.key});

  @override
  State<IccidScanPage> createState() => _IccidScanPageState();
}

class _IccidScanPageState extends State<IccidScanPage> {
  // Requests the camera permission through the system dialog on start.
  final _controller = MobileScannerController(formats: const [
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.qrCode,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.itf2of5,
  ]);
  String? _last;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue ?? '';
      final iccid = extractIccid(raw);
      if (iccid != null) {
        _done = true;
        Navigator.of(context).pop(iccid);
        return;
      }
      if (raw.isNotEmpty && raw != _last) setState(() => _last = raw);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('扫描卡托 ICCID 条码')),
        body: Stack(children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _Fallback(
                message:
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? '未获得相机权限，可在系统设置中开启，或返回手动输入'
                        : '相机不可用（${error.errorCode.name}），请返回手动输入'),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_last != null)
                Text('读到 "$_last"，不是有效 ICCID，继续对准条码',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              FilledButton(
                  key: const Key('scan-manual'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('改为手动输入')),
            ]),
          ),
        ]),
      );
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message,
                key: const Key('scan-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
          ),
        ),
      );
}
