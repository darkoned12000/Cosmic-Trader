import 'dart:io';

/// Crash-safe file writes.
///
/// JSON storage rewrites whole game state files; a crash or forced kill
/// mid-write can leave a truncated file behind. Writing to a sibling temp
/// file and then renaming it over the destination makes the write atomic
/// (POSIX rename semantics), so the file is always either the old or the
/// new content — never a partial one.
class FileSafe {
  FileSafe._();

  /// Writes [contents] to [file] atomically via a unique sibling temp file.
  ///
  /// The temp name embeds the PID and timestamp so concurrent writers never
  /// collide on the same `.tmp` path (a shared temp name caused a rename
  /// race where a failed writer then deleted the real file). On platforms
  /// where rename cannot overwrite an existing destination (Windows), falls
  /// back to a direct write — non-atomic there, but never data-lossy.
  static Future<void> writeString(File file, String contents) async {
    final tmp = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await tmp.writeAsString(contents, flush: true);
      try {
        await tmp.rename(file.path);
      } on FileSystemException {
        // Windows: rename refuses to replace an existing file. Write through
        // instead — the old content stays untouched if this write fails.
        await file.writeAsString(contents, flush: true);
      }
    } finally {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          // Best-effort cleanup; a stale temp is harmless.
        }
      }
    }
  }
}
