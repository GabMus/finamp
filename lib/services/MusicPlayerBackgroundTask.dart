import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:chopper/chopper.dart';
import 'package:finamp/services/FinampLogsHelper.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

import 'JellyfinApiData.dart';
import 'DownloadsHelper.dart';
import 'FinampSettingsHelper.dart';
import 'getInternalSongDir.dart';
import '../models/JellyfinModels.dart';
import '../main.dart';
import '../setupLogging.dart';

/// This provider handles the currently playing music so that multiple widgets can control music.
class MusicPlayerBackgroundTask extends BackgroundAudioTask {
  final _player = AudioPlayer();
  List<MediaItem> _queue = [];
  ConcatenatingAudioSource _queueAudioSource =
      ConcatenatingAudioSource(children: []);
  AudioProcessingState _skipState;
  StreamSubscription<PlaybackEvent> _eventSubscription;
  Box<DownloadedSong> _downloadedItemsBox;
  DateTime _lastUpdateTime;
  Logger audioServiceBackgroundTaskLogger;

  /// Set when shuffle mode is changed. If true, [onUpdateQueue] will create a shuffled [ConcatenatingAudioSource].
  bool shuffleNextQueue = false;

  @override
  Future<void> onStart(Map<String, dynamic> params) async {
    try {
      // Set up Hive in this isolate
      await setupHive();
      setupLogging();
      audioServiceBackgroundTaskLogger = Logger("MusicPlayerBackgroundTask");
      audioServiceBackgroundTaskLogger.info("Starting audio service");

      // Set up an instance of JellyfinApiData and DownloadsHelper since get_it can't talk across isolates
      GetIt.instance.registerLazySingleton(() => JellyfinApiData());
      GetIt.instance.registerLazySingleton(() => DownloadsHelper());

      _downloadedItemsBox = Hive.box("DownloadedItems");

      // Initialise FlutterDownloader in this isolate (only needed to check if file download is complete)
      await FlutterDownloader.initialize();

      // Broadcast that we're connecting, and what controls are available.
      _broadcastState();

      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.music());

      // These values will be null if we don't set them here
      await _player.setLoopMode(LoopMode.off);
      await _player.setShuffleModeEnabled(false);

      // Broadcast media item changes.
      _player.currentIndexStream.listen((index) {
        if (index != null) AudioServiceBackground.setMediaItem(_queue[index]);
      });

      // Propagate all events from the audio player to AudioService clients.
      _eventSubscription = _player.playbackEventStream.listen((event) {
        _broadcastState();

        // We don't want to attempt updating playback progress with the server if we're in offline mode
        // We also check if the player actually has the current index, since it is null when we first start playing
        if (!FinampSettingsHelper.finampSettings.isOffline &&
            _player.currentIndex != null) _updatePlaybackProgress();
      });

      await _broadcastState();

      // Special processing for state transitions.
      _player.processingStateStream.listen((state) {
        switch (state) {
          case ProcessingState.completed:
            // In this example, the service stops when reaching the end.
            onStop();
            break;
          case ProcessingState.ready:
            // If we just came from skipping between tracks, clear the skip
            // state now that we're ready to play.
            _skipState = null;
            break;
          default:
            break;
        }
      });
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onPlay() async {
    try {
      await _player.play();
      // Broadcast that we're playing, and what controls are available.
      _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onStop() async {
    try {
      JellyfinApiData jellyfinApiData = GetIt.instance<JellyfinApiData>();
      audioServiceBackgroundTaskLogger.info("Stopping audio service");

      // Tell Jellyfin we're no longer playing audio
      jellyfinApiData.stopPlaybackProgress(_generatePlaybackProgressInfo());

      // Stop playing audio.
      await _player.stop();
      await _player.dispose();
      await _eventSubscription.cancel();
      // It is important to wait for this state to be broadcast before we shut
      // down the task. If we don't, the background task will be destroyed before
      // the message gets sent to the UI.
      await _broadcastState();
      // Shut down this background task
      await super.onStop();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onPause() async {
    try {
      // Pause the audio.
      await _player.pause();
      // Broadcast that we're paused, and what controls are available.
      _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onAddQueueItem(MediaItem mediaItem) async {
    try {
      _queueAudioSource.add(await _mediaItemToAudioSource(mediaItem));
      await _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onUpdateQueue(List<MediaItem> newQueue) async {
    try {
      _queue = newQueue;

      // Convert the MediaItems to AudioSources
      List<AudioSource> audioSources = [];
      for (final mediaItem in _queue) {
        audioSources.add(await _mediaItemToAudioSource(mediaItem));
      }

      // Create a new ConcatenatingAudioSource with the new queue. If shuffleNextQueue is set, we shuffle songs.
      _queueAudioSource = ConcatenatingAudioSource(
        children: audioSources,
        shuffleOrder: shuffleNextQueue ? DefaultShuffleOrder() : null,
      );

      await _player.setAudioSource(_queueAudioSource);
      await _broadcastState();
      await AudioServiceBackground.setQueue(_queue);
      await AudioServiceBackground.setMediaItem(_queue[_player.currentIndex]);
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    try {
      await onStop();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onSkipToPrevious() async {
    try {
      await _player.seekToPrevious();
      await _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onSkipToNext() async {
    try {
      await _player.seekToNext();
      await _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onSeekTo(Duration position) async {
    try {
      await _player.seek(position);
      await _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onSetShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    try {
      switch (shuffleMode) {
        case AudioServiceShuffleMode.all:
          await _player.setShuffleModeEnabled(true);
          shuffleNextQueue = true;
          break;
        case AudioServiceShuffleMode.none:
          await _player.setShuffleModeEnabled(false);
          shuffleNextQueue = false;
          break;
        default:
          return Future.error(
              "Unsupported AudioServiceRepeatMode! Recieved ${shuffleMode.toString()}, requires all or none.");
      }
      await _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<void> onSetRepeatMode(AudioServiceRepeatMode repeatMode) async {
    try {
      switch (repeatMode) {
        case AudioServiceRepeatMode.all:
          await _player.setLoopMode(LoopMode.all);
          break;
        case AudioServiceRepeatMode.none:
          await _player.setLoopMode(LoopMode.off);
          break;
        case AudioServiceRepeatMode.one:
          await _player.setLoopMode(LoopMode.one);
          break;
        default:
          return Future.error(
              "Unsupported AudioServiceRepeatMode! Recieved ${repeatMode.toString()}, requires all, none, or one.");
      }
      await _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  @override
  Future<dynamic> onCustomAction(String name, dynamic arguments) async {
    try {
      switch (name) {
        case "removeQueueItem":
          await _removeQueueItemAt(arguments);
          break;
        case "getLogs":
          FinampLogsHelper finampLogsHelper =
              GetIt.instance<FinampLogsHelper>();
          return jsonEncode(finampLogsHelper.logs);
        case "copyLogs":
          FinampLogsHelper finampLogsHelper =
              GetIt.instance<FinampLogsHelper>();
          await finampLogsHelper.copyLogs();
          break;
        default:
          return Future.error("Invalid custom action!");
      }
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  /// Broadcasts the current state to all clients.
  Future<void> _broadcastState() async {
    try {
      await AudioServiceBackground.setState(
          controls: [
            MediaControl.skipToPrevious,
            if (_player.playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: [
            MediaAction.seekTo,
            MediaAction.seekForward,
            MediaAction.seekBackward,
            MediaAction.skipToQueueItem,
          ],
          processingState: _getProcessingState(),
          playing: _player.playing,
          position: _player.position,
          bufferedPosition: _player.bufferedPosition,
          repeatMode: _getRepeatMode(),
          shuffleMode: _getShuffleMode());
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  Future<void> _updatePlaybackProgress() async {
    try {
      JellyfinApiData jellyfinApiData = GetIt.instance<JellyfinApiData>();

      if (_lastUpdateTime == null ||
          DateTime.now().millisecondsSinceEpoch -
                  _lastUpdateTime.millisecondsSinceEpoch >=
              10000) {
        Response response = await jellyfinApiData
            .updatePlaybackProgress(_generatePlaybackProgressInfo());

        if (response.isSuccessful) {
          _lastUpdateTime = DateTime.now();
        }
      }
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  /// Maps just_audio's processing state into into audio_service's playing
  /// state. If we are in the middle of a skip, we use [_skipState] instead.
  AudioProcessingState _getProcessingState() {
    if (_skipState != null) return _skipState;
    switch (_player.processingState) {
      case ProcessingState.idle:
        return AudioProcessingState.stopped;
      case ProcessingState.loading:
        return AudioProcessingState.connecting;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      default:
        throw Exception("Invalid state: ${_player.processingState}");
    }
  }

  AudioServiceRepeatMode _getRepeatMode() {
    switch (_player.loopMode) {
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
        break;
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
        break;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
        break;
      default:
        throw ("Unsupported AudioServiceRepeatMode! Recieved ${_player.loopMode.toString()}, requires all, off, or one.");
    }
  }

  AudioServiceShuffleMode _getShuffleMode() {
    if (_player.shuffleModeEnabled) {
      return AudioServiceShuffleMode.all;
    } else {
      return AudioServiceShuffleMode.none;
    }
  }

  /// Syncs the list of MediaItems (_queue) with the internal queue of the player.
  /// Called by onAddQueueItem and onUpdateQueue.
  Future<AudioSource> _mediaItemToAudioSource(MediaItem mediaItem) async {
    try {
      // TODO: If the audio service is already running, boxes may be out of sync with the rest of the app, meaning that some songs may not play locally.

      DownloadsHelper downloadsHelper = GetIt.instance<DownloadsHelper>();

      if (_downloadedItemsBox.containsKey(mediaItem.id)) {
        String downloadId = _downloadedItemsBox.get(mediaItem.id).downloadId;
        List<DownloadTask> downloadTaskList =
            await FlutterDownloader.loadTasksWithRawQuery(
                query: "SELECT * FROM task WHERE task_id='$downloadId'");
        DownloadTask downloadTask = downloadTaskList[0];

        if (downloadTask.status == DownloadTaskStatus.complete) {
          audioServiceBackgroundTaskLogger
              .info("Song exists offline, using local file");
          DownloadedSong downloadedSong = _downloadedItemsBox.get(mediaItem.id);

          // If downloadedSong.path is null, this song was probably downloaded before custom storage locations (0.4.0).
          // Before 0.4.0, all songs were located in internalSongDir. We assume the song is located there, and set the path accordingly.
          if (downloadedSong.path == null) {
            audioServiceBackgroundTaskLogger.info(
                "downloadedSong.path for ${mediaItem.id} is null, migrating and assuming location is internal storage");

            Directory songDir = await getInternalSongDir();

            downloadedSong.path =
                "${songDir.path}/${mediaItem.id}.${downloadedSong.mediaSourceInfo.container}";
            _downloadedItemsBox.put(mediaItem.id, downloadedSong);
          }

          // Here we check if the file exists. This is important for human-readable files, since the user could have deleted the file.
          if (!await File(downloadedSong.path).exists()) {
            // If the file was not found, delete it in DownloadsHelper so that it properly shows as deleted.
            audioServiceBackgroundTaskLogger.warning(
                "${downloadedSong.song.name} not found! Deleting with DownloadsHelper");
            downloadsHelper.deleteDownloads([downloadedSong.song.id]);

            // If offline, throw an error. Otherwise, return a regular URL source.
            if (FinampSettingsHelper.finampSettings.isOffline) {
              return Future.error(
                  "File could not be found. Not falling back to online stream due to offline mode");
            } else {
              return AudioSource.uri(_songUri(mediaItem));
            }
          }

          return AudioSource.uri(Uri.file(downloadedSong.path));
        } else {
          if (FinampSettingsHelper.finampSettings.isOffline) {
            return Future.error(
                "Download is not complete, not adding. Wait for all downloads to be complete before playing.");
          } else {
            return AudioSource.uri(
              _songUri(mediaItem),
            );
          }
        }
      } else {
        return AudioSource.uri(
          _songUri(mediaItem),
        );
      }
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  Uri _songUri(MediaItem mediaItem) {
    JellyfinApiData jellyfinApiData = GetIt.instance<JellyfinApiData>();
    if (FinampSettingsHelper.finampSettings.shouldTranscode) {
      audioServiceBackgroundTaskLogger.info("Using transcode URL");
      int transcodeBitRate =
          FinampSettingsHelper.finampSettings.transcodeBitrate;
      return Uri.parse(
          "${jellyfinApiData.currentUser.baseUrl}/Audio/${mediaItem.id}/stream?audioBitRate=$transcodeBitRate&audioCodec=aac&static=false");
    } else {
      return Uri.parse(
          "${jellyfinApiData.currentUser.baseUrl}/Audio/${mediaItem.id}/stream?static=true");
    }
  }

  /// audio_service doesn't have a removeQueueItemAt so I wrote my own.
  /// Pops an item from the queue with the given index and refreshes the queue.
  Future<void> _removeQueueItemAt(int index) async {
    try {
      _queue.removeAt(index);
      _queueAudioSource.removeAt(index);
      await _broadcastState();
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      return Future.error(e);
    }
  }

  /// Generates PlaybackProgressInfo from current player info
  PlaybackProgressInfo _generatePlaybackProgressInfo() {
    try {
      return PlaybackProgressInfo(
          itemId: _queue[_player.currentIndex].id,
          isPaused: !_player.playing,
          isMuted: _player.volume == 0,
          positionTicks: _player.position.inMicroseconds * 10,
          repeatMode: _convertRepeatMode(_player.loopMode));
    } catch (e) {
      audioServiceBackgroundTaskLogger.severe(e);
      rethrow;
    }
  }
}

String _convertRepeatMode(LoopMode loopMode) {
  switch (loopMode) {
    case LoopMode.all:
      return "RepeatAll";
      break;
    case LoopMode.one:
      return "RepeatOne";
      break;
    case LoopMode.off:
      return "RepeatNone";
      break;
    default:
      return "RepeatNone";
      break;
  }
}
