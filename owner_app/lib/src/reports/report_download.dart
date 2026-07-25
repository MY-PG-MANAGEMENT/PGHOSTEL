import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

/// Test seam for the "open it after saving" step. `OpenFilex` launches a real
/// process on desktop (`cmd /c start` on Windows), which a widget test must not
/// do — tests set this to record the path instead.
@visibleForTesting
Future<bool> Function(String path)? debugOpenSavedFile;

/// Where a downloaded report ended up.
class SavedReport {
  const SavedReport({required this.path, required this.folder, this.opened = true});

  /// Full path on disk; empty on web, where the browser owns the download.
  final String path;

  /// Short, human-facing folder name for the confirmation toast.
  final String folder;

  /// Whether the PDF was handed to a viewer after saving.
  final bool opened;
}

/// Writes [bytes] straight to storage and opens it — **no folder chooser and no
/// share sheet**. The owner taps Download and the PDF appears.
///
/// * Android/iOS: the app's documents/external directory (no runtime permission
///   needed on any API level, unlike the public Downloads folder under scoped
///   storage), then handed to the system viewer via `open_filex`.
/// * Desktop: the real Downloads folder when the platform exposes one.
/// * Web: there is no filesystem, so this falls back to `Printing.sharePdf`,
///   which on web is just a browser download.
Future<SavedReport> savePdfToDevice(Uint8List bytes, String filename) async {
  if (kIsWeb) {
    await Printing.sharePdf(bytes: bytes, filename: filename);
    return const SavedReport(path: '', folder: 'Downloads', opened: false);
  }

  final dir = await _targetDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);

  final opened = debugOpenSavedFile != null
      ? await debugOpenSavedFile!(file.path)
      : (await OpenFilex.open(file.path, type: 'application/pdf')).type ==
          ResultType.done;
  return SavedReport(
    path: file.path,
    folder: _folderLabel(dir.path),
    opened: opened,
  );
}

Future<Directory> _targetDirectory() async {
  if (Platform.isAndroid) {
    // App-specific external storage: visible to file managers, writable without
    // MANAGE_EXTERNAL_STORAGE, and never cleared behind the user's back.
    final external = await getExternalStorageDirectory();
    if (external != null) {
      final reports = Directory('${external.path}${Platform.pathSeparator}Reports');
      if (!await reports.exists()) await reports.create(recursive: true);
      return reports;
    }
  }
  if (!Platform.isIOS) {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {
      // Not supported on this platform — fall through to documents.
    }
  }
  return getApplicationDocumentsDirectory();
}

/// Last path segment, so the toast can say "saved to Reports" rather than
/// echoing an unreadable absolute path.
String _folderLabel(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? 'device storage' : parts.last;
}
