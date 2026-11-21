import 'dart:io';

/// Writes [content] to the user's Downloads folder (created if missing) and
/// returns the absolute path, or null if the filesystem is unavailable.
Future<String?> saveTextFile(String fileName, String content) async {
  try {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final dir = Directory('$home${Platform.pathSeparator}Downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final dot = safe.lastIndexOf('.');
    final stem = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    var file = File('${dir.path}${Platform.pathSeparator}$safe');
    for (var n = 2; file.existsSync(); n++) {
      file = File('${dir.path}${Platform.pathSeparator}$stem($n)$ext');
    }
    await file.writeAsString(content, flush: true);
    return file.path;
  } on FileSystemException {
    return null;
  }
}
