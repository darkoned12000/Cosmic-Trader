import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/game_settings.dart';
import 'package:tradewars_2050/services/audio_service.dart';

class AudioSettingsWidget extends StatelessWidget {
  final double musicVolume;
  final double sfxVolume;
  final ValueChanged<double> onMusicVolumeChanged;
  final ValueChanged<double> onSfxVolumeChanged;
  final ValueChanged<GameSettings>? onSaveSettings;
  final GameSettings Function() buildSettings;

  const AudioSettingsWidget({
    super.key,
    required this.musicVolume,
    required this.sfxVolume,
    required this.onMusicVolumeChanged,
    required this.onSfxVolumeChanged,
    required this.buildSettings,
    this.onSaveSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.2)),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(Icons.audiotrack_rounded, color: accent),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('▒ ',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w100,
                      color: accent.withValues(alpha: 0.5))),
              Text('AUDIO SYSTEMS',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  )),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(context, 'VOLUME CONTROLS'),
                  const SizedBox(height: 8),
                  _volumeSlider(
                    context,
                    label: 'MUSIC',
                    icon: Icons.music_note_rounded,
                    value: musicVolume,
                    onChanged: onMusicVolumeChanged,
                    onChangeEnd: (_) =>
                        onSaveSettings?.call(buildSettings()),
                  ),
                  const SizedBox(height: 4),
                  _volumeSlider(
                    context,
                    label: 'SFX',
                    icon: Icons.volume_up_rounded,
                    value: sfxVolume,
                    onChanged: onSfxVolumeChanged,
                    onChangeEnd: (_) =>
                        onSaveSettings?.call(buildSettings()),
                  ),

                  const SizedBox(height: 16),
                  _divider(accent),
                  const SizedBox(height: 16),

                  _sectionLabel(context, 'MUSIC ARCHIVE'),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: AudioService.musicFolderPath,
                    builder: (context, _) => _folderPanel(context),
                  ),

                  const SizedBox(height: 16),
                  _divider(accent),
                  const SizedBox(height: 16),

                  _sectionLabel(context, 'TRANSMISSION QUEUE'),
                  const SizedBox(height: 8),
                  _trackListHeader(context),
                  const SizedBox(height: 4),
                  _trackList(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: accent.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _divider(Color accent) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.4),
            accent.withValues(alpha: 0.1),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _volumeSlider(
    BuildContext context, {
    required String label,
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final dimText = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: dimText,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Text(
                  '${(value * 100).round().toString().padLeft(3)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.15),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.12),
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              divisions: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderPanel(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: accent.withValues(alpha: 0.15), width: 0.5),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                'SOURCE DIRECTORY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: accent.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AudioService.musicFolderPath.value,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await AudioService.instance.browseFolder();
                onSaveSettings?.call(buildSettings());
              },
              icon: Icon(Icons.explore_rounded, size: 16, color: accent),
              label: Text(
                'SCAN DIRECTORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: accent,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                padding:
                    const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackListHeader(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final dimText = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Row(
      children: [
        Icon(Icons.playlist_play_rounded, size: 16, color: accent),
        const SizedBox(width: 6),
        Text(
          'AVAILABLE SIGNALS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: dimText,
          ),
        ),
        const Spacer(),
        ListenableBuilder(
          listenable: AudioService.loopMode,
          builder: (context, _) {
            final mode = AudioService.loopMode.value;
            final (icon, tooltip) = switch (mode) {
              LoopMode.none => (Icons.repeat_rounded, 'No repeat'),
              LoopMode.single =>
                (Icons.repeat_one_rounded, 'Repeat one'),
              LoopMode.all => (Icons.repeat_rounded, 'Repeat all'),
            };
            return IconButton(
              icon: Icon(icon, size: 18,
                  color: mode != LoopMode.none
                      ? accent
                      : dimText),
              tooltip: tooltip,
              onPressed: () => AudioService.instance.cycleLoopMode(),
              visualDensity: VisualDensity.compact,
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.shuffle_rounded, size: 18, color: dimText),
          tooltip: 'Play random track',
          onPressed: () => AudioService.instance.playRandom(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _trackList(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;

    return ListenableBuilder(
      listenable: Listenable.merge([
        AudioService.musicFiles,
        AudioService.currentTrack,
        AudioService.isPlaying,
      ]),
      builder: (context, _) {
        final files = AudioService.musicFiles.value;
        final current = AudioService.currentTrack.value;
        final playing = AudioService.isPlaying.value;

        if (files.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '-- NO SIGNALS DETECTED --',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: accent.withValues(alpha: 0.1), width: 0.5),
          ),
          child: Column(
            children: List.generate(files.length, (i) {
              final file = files[i];
              final name = file.split('/').last;
              final isCurrent = current == name;
              return InkWell(
                onTap: () {
                  if (isCurrent && playing) {
                    AudioService.instance.togglePlayPause();
                  } else if (isCurrent) {
                    AudioService.instance.togglePlayPause();
                  } else {
                    AudioService.instance.playTrack(i);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: cs.onSurface.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        alignment: Alignment.center,
                        child: isCurrent
                            ? Icon(
                                playing
                                    ? Icons.equalizer_rounded
                                    : Icons.pause_circle_filled_rounded,
                                size: 16,
                                color: accent,
                              )
                            : Icon(
                                Icons.radio_button_unchecked_rounded,
                                size: 12,
                                color:
                                    cs.onSurface.withValues(alpha: 0.3),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrent
                                ? accent
                                : cs.onSurface
                                    .withValues(alpha: 0.8),
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent && playing)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'ONLINE',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
