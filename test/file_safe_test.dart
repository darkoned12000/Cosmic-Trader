import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/storage/file_safe.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_safe_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File targetFile() => File('${tempDir.path}/test.json');

  test('writes content to a new file', () async {
    final file = targetFile();
    await FileSafe.writeString(file, '{"a":1}');
    expect(await file.readAsString(), '{"a":1}');
  });

  test('overwrites existing content', () async {
    final file = targetFile();
    await FileSafe.writeString(file, 'old');
    await FileSafe.writeString(file, 'new');
    expect(await file.readAsString(), 'new');
  });

  test('leaves no temp files behind', () async {
    final file = targetFile();
    await FileSafe.writeString(file, 'data');
    final leftovers = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'));
    expect(leftovers, isEmpty);
  });

  test('concurrent writes never corrupt or delete the target file', () async {
    // Regression: the original implementation used one shared `.tmp` name,
    // so two overlapping saves raced — one rename failed and the error
    // handler deleted the real file. Unique temp names must prevent that.
    final file = targetFile();
    final writes = List.generate(
      20,
      (i) => FileSafe.writeString(file, '{"write":$i}'),
    );
    await Future.wait(writes);

    expect(await file.exists(), isTrue, reason: 'target file must survive');
    final content = await file.readAsString();
    expect(content, matches(RegExp(r'^\{"write":\d+\}$')),
        reason: 'content must be a complete, valid write');
  });
}
