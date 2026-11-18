import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/core/widgets/buddy_widgets.dart';
import 'package:hello_buddy/services/esp32_service.dart';

class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String streamUrl;
  final String? artworkUrl;
  final int durationSeconds;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.streamUrl,
    this.artworkUrl,
    this.durationSeconds = 180,
  });
}

class SoundscapeScreen extends StatefulWidget {
  const SoundscapeScreen({super.key});

  @override
  State<SoundscapeScreen> createState() => _SoundscapeScreenState();
}

class _SoundscapeScreenState extends State<SoundscapeScreen> {
  final _audioPlayer = AudioPlayer();
  final _esp32 = Esp32Service();
  final _searchController = TextEditingController();

  List<MusicTrack> _tracks = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = false;
  double _volume = 0.85;
  int _routeIndex = 0; // 0 = Phone, 1 = Robot Speaker

  // Preloaded popular study/focus tracks (Audius open network)
  final List<MusicTrack> _defaultTracks = const [
    MusicTrack(
      id: '95wro',
      title: 'Stars In The Sky (Lofi Beats)',
      artist: 'Lofi Beats Official',
      streamUrl: 'https://discoveryprovider.audius.co/v1/tracks/95wro/stream?app_name=HELLOBUDDY',
      artworkUrl: 'https://creatornode.audius.co/content/QmVqupGHZuhjxAgePsiZYyRFkvPUMrzsHMkDVaaGrGUzDK/150x150.jpg',
      durationSeconds: 195,
    ),
    MusicTrack(
      id: 'W08NKdZ',
      title: 'Midnight Focus Ambient',
      artist: 'Electronic Sanctuary',
      streamUrl: 'https://discoveryprovider.audius.co/v1/tracks/W08NKdZ/stream?app_name=HELLOBUDDY',
      artworkUrl: 'https://audius-01.staked.cloud/content/baeaaaiqsedszpcmjuiem7b5qilvws4622vnsrht4ybnlqldmfzgxogcogawsa/150x150.jpg',
      durationSeconds: 240,
    ),
    MusicTrack(
      id: 'lofi_zeno_live',
      title: '24/7 Lofi Girl Study Stream',
      artist: 'Focus FM Radio',
      streamUrl: 'https://stream.zeno.fm/f3wvbbqmdg8uv',
      durationSeconds: 0,
    ),
  ];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tracks = List.from(_defaultTracks);
    _setupAudioPlayer();
    _searchAudiusTracks('lofi study');
  }

  void _setupAudioPlayer() {
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        _isLoading = state.processingState == ProcessingState.buffering ||
            state.processingState == ProcessingState.loading;
      });
    });

    _audioPlayer.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });

    _audioPlayer.durationStream.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur ?? Duration.zero);
    });
  }

  Future<void> _searchAudiusTracks(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse(
          'https://discoveryprovider.audius.co/v1/tracks/search?query=${Uri.encodeComponent(clean)}&app_name=HELLOBUDDY&limit=12');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'] as List<dynamic>? ?? [];

        final fetched = <MusicTrack>[];
        for (final item in data) {
          final id = item['id']?.toString() ?? '';
          final title = item['title']?.toString() ?? 'Untitled Track';
          final user = item['user'] as Map<dynamic, dynamic>? ?? {};
          final artist = user['name']?.toString() ?? 'Independent Artist';
          final artworkMap = item['artwork'] as Map<dynamic, dynamic>?;
          final artwork = artworkMap?['150x150']?.toString();
          final duration = (item['duration'] as int?) ?? 180;

          if (id.isNotEmpty) {
            fetched.add(MusicTrack(
              id: id,
              title: title,
              artist: artist,
              streamUrl:
                  'https://discoveryprovider.audius.co/v1/tracks/$id/stream?app_name=HELLOBUDDY',
              artworkUrl: artwork,
              durationSeconds: duration,
            ));
          }
        }

        if (fetched.isNotEmpty && mounted) {
          setState(() {
            _tracks = fetched;
            _currentIndex = 0;
          });
        }
      }
    } catch (_) {
      // Fallback to defaults
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;

    setState(() {
      _currentIndex = index;
      _isLoading = true;
    });

    try {
      await _audioPlayer.stop();
      await _audioPlayer.setUrl(_tracks[index].streamUrl);
      await _audioPlayer.setVolume(_volume);
      await _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stream notice: $e'),
            backgroundColor: BuddyColors.carbon,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_audioPlayer.audioSource == null) {
        await _playTrack(_currentIndex);
      } else {
        await _audioPlayer.play();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final current = _tracks.isNotEmpty ? _tracks[_currentIndex] : _defaultTracks[0];

    return Scaffold(
      backgroundColor: BuddyColors.bone,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 14),
                  _buildPlayerCard(current),
                  const SizedBox(height: 14),
                  _buildAudioRouting(),
                  const SizedBox(height: 14),
                  _buildTrackList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: BuddyColors.carbon,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 4)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: BuddyColors.lime,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BuddyColors.pitch, width: 2),
                    ),
                    child: const Icon(Icons.music_note_rounded, color: BuddyColors.onLime, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AUDIUS MUSIC API',
                    style: BuddyTheme.displayFont(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BuddyColors.bone,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: BuddyColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: BuddyColors.smoke.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isPlaying ? Icons.graphic_eq : Icons.headphones,
                      color: BuddyColors.lime,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isPlaying ? 'STREAMING' : 'IDLE',
                      style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.lime),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BuddyColors.pitch, width: 1.5),
        boxShadow: const [BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 20, color: BuddyColors.smoke),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: _searchAudiusTracks,
              style: BuddyTheme.bodyFont(fontSize: 12, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Search songs, lofi, ambient, chill beats...',
                hintStyle: BuddyTheme.bodyFont(fontSize: 12, color: BuddyColors.smoke),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _searchAudiusTracks(_searchController.text),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: BuddyColors.lime,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BuddyColors.pitch, width: 1),
              ),
              child: Text(
                'Search',
                style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.onLime),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(MusicTrack track) {
    return BuddyCard(
      fill: BuddyColors.bone,
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: BuddyColors.carbon,
                    border: Border.all(color: BuddyColors.pitch, width: 1.5),
                  ),
                  child: track.artworkUrl != null
                      ? Image.network(
                          track.artworkUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.music_note, color: BuddyColors.lime),
                        )
                      : const Icon(Icons.headphones_rounded, color: BuddyColors.lime, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: BuddyTheme.displayFont(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: BuddyColors.carbon,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      style: BuddyTheme.bodyFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BuddyColors.smoke,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Duration slider
          if (_duration.inSeconds > 0) ...[
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: BuddyColors.lime,
                inactiveTrackColor: const Color(0xFFDDDCD6),
                thumbColor: BuddyColors.carbon,
                trackHeight: 5,
              ),
              child: Slider(
                value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                max: _duration.inSeconds.toDouble(),
                onChanged: (val) {
                  _audioPlayer.seek(Duration(seconds: val.toInt()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_position),
                      style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.smoke)),
                  Text(_formatDuration(_duration),
                      style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.smoke)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Playback Buttons (Scale-down safe, zero overflow)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ControlButton(
                  icon: Icons.skip_previous_rounded,
                  label: 'Prev',
                  onTap: () {
                    final prev = (_currentIndex - 1 + _tracks.length) % _tracks.length;
                    _playTrack(prev);
                  },
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    decoration: BuddyDecorations.pill(fill: BuddyColors.lime),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: BuddyColors.onLime),
                          )
                        else
                          Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: BuddyColors.onLime,
                            size: 22,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          _isLoading
                              ? 'Buffering...'
                              : (_isPlaying ? 'Pause' : 'Play Song'),
                          style: BuddyTheme.displayFont(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: BuddyColors.onLime,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ControlButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Next',
                  onTap: () {
                    final next = (_currentIndex + 1) % _tracks.length;
                    _playTrack(next);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioRouting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'AUDIO DESTINATION ROUTING',
            style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.smoke),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _routeIndex = 0),
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.all(10),
                  decoration: BuddyDecorations.cardSmall(
                    fill: _routeIndex == 0 ? BuddyColors.lime : Colors.white,
                    radius: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        size: 22,
                        color: _routeIndex == 0 ? BuddyColors.onLime : BuddyColors.carbon,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Phone Audio',
                            style: BuddyTheme.bodyFont(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _routeIndex == 0 ? BuddyColors.onLime : BuddyColors.carbon,
                            ),
                          ),
                          Text(
                            'Headset / Internal',
                            style: BuddyTheme.captionMono(fontSize: 8, color: BuddyColors.smoke),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  setState(() => _routeIndex = 1);
                  try {
                    await _esp32.playTone('chime');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Chimed on Robot Speaker (MAX98357A)!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Robot audio error: $e')),
                      );
                    }
                  }
                },
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.all(10),
                  decoration: BuddyDecorations.cardSmall(
                    fill: _routeIndex == 1 ? BuddyColors.lime : Colors.white,
                    radius: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.speaker_rounded,
                        size: 22,
                        color: _routeIndex == 1 ? BuddyColors.onLime : BuddyColors.carbon,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Robot Speaker',
                            style: BuddyTheme.bodyFont(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _routeIndex == 1 ? BuddyColors.onLime : BuddyColors.carbon,
                            ),
                          ),
                          Text(
                            'MAX98357A I2S DAC',
                            style: BuddyTheme.captionMono(fontSize: 8, color: BuddyColors.smoke),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrackList() {
    return BuddyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AUDIUS TRACKS (${_tracks.length})',
                style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
              ),
              Text(
                'Open Free API',
                style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.smoke),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._tracks.asMap().entries.map((entry) {
            final idx = entry.key;
            final t = entry.value;
            final isSelected = _currentIndex == idx;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected ? BuddyColors.lime.withValues(alpha: 0.3) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? BuddyColors.pitch : const Color(0xFFDDDCD6),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 36,
                    height: 36,
                    color: BuddyColors.carbon,
                    child: t.artworkUrl != null
                        ? Image.network(
                            t.artworkUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.music_note, color: Colors.white, size: 18),
                          )
                        : const Icon(Icons.music_note, color: Colors.white, size: 18),
                  ),
                ),
                title: Text(
                  t.title,
                  style: BuddyTheme.bodyFont(fontSize: 12, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  t.artist,
                  style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.smoke),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isSelected && _isPlaying
                    ? const Icon(Icons.volume_up_rounded, color: BuddyColors.pitch, size: 20)
                    : const Icon(Icons.play_circle_outline_rounded, color: BuddyColors.smoke, size: 20),
                onTap: () => _playTrack(idx),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BuddyDecorations.cardSmall(fill: Colors.white, radius: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: BuddyColors.carbon),
            const SizedBox(width: 4),
            Text(
              label,
              style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.carbon),
            ),
          ],
        ),
      ),
    );
  }
}
