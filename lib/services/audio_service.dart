import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

enum LoopMode { none, single, all }

class AudioService {
  AudioService._();

  static AudioService? _instance;
  static AudioService get instance => _instance ??= AudioService._();

  static final musicVolume = ValueNotifier<double>(0.5);
  static final sfxVolume = ValueNotifier<double>(0.7);
  static final musicFolderPath = ValueNotifier<String>('assets/music');
  static final musicFiles = ValueNotifier<List<String>>([]);
  static final currentTrack = ValueNotifier<String?>(null);
  static final isPlaying = ValueNotifier<bool>(false);
  static final isMusicEnabled = ValueNotifier<bool>(true);
  static final loopMode = ValueNotifier<LoopMode>(LoopMode.all);

  late final AudioPlayer _musicPlayer;
  late final AudioPlayer _sfxPlayer;
  final _audioExtensions = {'.mp3', '.wav', '.ogg'};

  int _currentTrackIndex = 0;

  Future<void> init() async {
    _musicPlayer = AudioPlayer();
    _sfxPlayer = AudioPlayer();

    musicVolume.addListener(_onMusicVolumeChanged);
    sfxVolume.addListener(_onSfxVolumeChanged);

    await _musicPlayer.setVolume(musicVolume.value);
    await _sfxPlayer.setVolume(sfxVolume.value);

    _musicPlayer.onPlayerComplete.listen((_) => _onTrackComplete());
    _musicPlayer.onPlayerStateChanged.listen((state) {
      isPlaying.value = state == PlayerState.playing;
    });

    final defaultDir = '${Directory.current.path}/assets/music';
    if (await Directory(defaultDir).exists()) {
      musicFolderPath.value = defaultDir;
    }
    await _scanFolder(musicFolderPath.value);

    if (musicFiles.value.isNotEmpty) {
      final starTrack = musicFiles.value.indexWhere(
        (f) => f.endsWith('Star-Light_Looping.ogg'),
      );
      if (starTrack >= 0) {
        loopMode.value = LoopMode.single;
        await playTrack(starTrack);
      }
    }
  }

  void _onMusicVolumeChanged() {
    _musicPlayer.setVolume(musicVolume.value);
  }

  void _onSfxVolumeChanged() {
    _sfxPlayer.setVolume(sfxVolume.value);
  }

  Future<void> _scanFolder(String path) async {
    final files = <String>[];
    if (path.startsWith('assets/')) {
      try {
        final manifest = await rootBundle.loadString('AssetManifest.json');
        final assets = manifest
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => l.trim().split(':')[0].replaceAll('"', '').trim())
            .where((p) => p.startsWith(path))
            .where((p) => _audioExtensions.any((ext) => p.endsWith(ext)))
            .toList();
        files.addAll(assets);
      } catch (_) {}
    } else {
      final dir = Directory(path);
      if (await dir.exists()) {
        await for (final entry in dir.list()) {
          if (entry is File &&
              _audioExtensions.any((ext) => entry.path.endsWith(ext))) {
            files.add(entry.path);
          }
        }
      }
    }
    files.sort();
    musicFiles.value = files;
    _currentTrackIndex = 0;
  }

  Future<void> browseFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Music Folder',
    );
    if (result != null) {
      musicFolderPath.value = result;
      await _scanFolder(result);
    }
  }

  Future<void> playMusic(String filePath) async {
    try {
      Source source;
      if (filePath.startsWith('assets/')) {
        source = AssetSource(filePath);
      } else {
        source = DeviceFileSource(filePath);
      }
      await _musicPlayer.stop();
      await _musicPlayer.play(source);
      currentTrack.value = _fileName(filePath);
    } catch (_) {}
  }

  Future<void> playTrack(int index) async {
    final files = musicFiles.value;
    if (index < 0 || index >= files.length) return;
    _currentTrackIndex = index;
    await playMusic(files[index]);
  }

  Future<void> playRandom() async {
    final files = musicFiles.value;
    if (files.isEmpty) return;
    final rng = math.Random();
    int newIndex;
    do {
      newIndex = rng.nextInt(files.length);
    } while (newIndex == _currentTrackIndex && files.length > 1);
    await playTrack(newIndex);
  }

  void _onTrackComplete() {
    switch (loopMode.value) {
      case LoopMode.none:
        currentTrack.value = null;
      case LoopMode.single:
        final files = musicFiles.value;
        if (_currentTrackIndex < files.length) {
          playMusic(files[_currentTrackIndex]);
        }
      case LoopMode.all:
        final files = musicFiles.value;
        if (files.isEmpty) return;
        _currentTrackIndex = (_currentTrackIndex + 1) % files.length;
        playMusic(files[_currentTrackIndex]);
    }
  }

  Future<void> togglePlayPause() async {
    if (!isMusicEnabled.value) return;
    if (_musicPlayer.state == PlayerState.playing) {
      await _musicPlayer.pause();
    } else {
      if (currentTrack.value == null && musicFiles.value.isNotEmpty) {
        await playTrack(0);
      } else {
        await _musicPlayer.resume();
      }
    }
  }

  Future<void> stopMusic() async {
    await _musicPlayer.stop();
    currentTrack.value = null;
  }

  Future<void> cycleLoopMode() async {
    loopMode.value = switch (loopMode.value) {
      LoopMode.none => LoopMode.single,
      LoopMode.single => LoopMode.all,
      LoopMode.all => LoopMode.none,
    };
  }

  Future<void> toggleMusicEnabled() async {
    isMusicEnabled.value = !isMusicEnabled.value;
    if (isMusicEnabled.value) {
      if (currentTrack.value == null && musicFiles.value.isNotEmpty) {
        await playTrack(0);
      } else {
        await _musicPlayer.resume();
      }
    } else {
      await _musicPlayer.pause();
    }
  }

  Future<void> playSfx(String filePath) async {
    try {
      Source source;
      if (filePath.startsWith('assets/')) {
        source = AssetSource(filePath);
      } else {
        source = DeviceFileSource(filePath);
      }
      await _sfxPlayer.stop();
      await _sfxPlayer.play(source);
    } catch (_) {}
  }

  String _fileName(String path) {
    return path.split('/').last;
  }

  void applySettings({
    required double musicVol,
    required double sfxVol,
    required String folderPath,
  }) {
    musicVolume.value = musicVol;
    sfxVolume.value = sfxVol;
    if (folderPath != musicFolderPath.value) {
      musicFolderPath.value = folderPath;
      _scanFolder(folderPath);
    }
  }

  Future<void> dispose() async {
    await _musicPlayer.dispose();
    await _sfxPlayer.dispose();
  }
}
