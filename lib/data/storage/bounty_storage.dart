import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:cosmic_trader/data/models/bounty.dart';
import 'package:cosmic_trader/data/storage/file_safe.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:path_provider/path_provider.dart';

/// File-backed bounty persistence (bounties.json). The live board lives in
/// [BountyBoard]; this store only reads/writes the file.
class BountyStorage {
  BountyStorage._();
  static final BountyStorage instance = BountyStorage._();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/bounties.json');
  }

  Future<({List<Bounty> active, List<PaidBounty> paid})> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return (active: <Bounty>[], paid: <PaidBounty>[]);
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final active = ((json['active'] as List?) ?? [])
          .map((e) => Bounty.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final paid = ((json['paid'] as List?) ?? [])
          .map((e) => PaidBounty.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      return (active: active, paid: paid);
    } catch (e) {
      // Never silent: a failed load explains every "bounties vanished"
      // mystery that follows.
      debugPrint('[BountyStorage] Load failed: $e');
      GameEventLog.global.system('[BountyStorage] Load failed: $e');
      return (active: <Bounty>[], paid: <PaidBounty>[]);
    }
  }

  Future<void> saveAll(List<Bounty> active, List<PaidBounty> paid) async {
    try {
      final file = await _file();
      await FileSafe.writeString(
        file,
        jsonEncode({
          'active': active.map((b) => b.toJson()).toList(),
          'paid': paid.map((b) => b.toJson()).toList(),
        }),
      );
    } catch (e) {
      debugPrint('[BountyStorage] Save failed: $e');
      GameEventLog.global.system('[BountyStorage] Save failed: $e');
    }
  }
}
