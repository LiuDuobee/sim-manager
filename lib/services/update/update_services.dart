import 'package:package_info_plus/package_info_plus.dart';

import 'update_host.dart';
import 'update_logic.dart';

/// Checker plus platform host, injected into the app so tests stay offline.
class UpdateServices {
  UpdateServices({required this.checker, required this.host});

  factory UpdateServices.platform() {
    final host = PlatformUpdateHost();
    return UpdateServices(
      host: host,
      checker: UpdateChecker(
        fetch: host.getString,
        currentVersion: () async => (await PackageInfo.fromPlatform()).version,
      ),
    );
  }

  final UpdateChecker checker;
  final UpdateHost host;
}
