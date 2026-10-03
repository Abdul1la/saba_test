import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'live_updates.dart';

/// The server's side of [LiveUpdates]: `GET /events`, a stream of one line
/// per change (`data: {"topic":"orders","id":"12"}`), turned into the same
/// announcements the app makes for its own writes.
///
/// Opened through the app's own [Dio], so the access token is attached, and
/// renewed first when it has run out, exactly as for every other request.
/// The server ends the stream when that token ends (15 minutes at most), and
/// a network drop or a restart ends it too: it opens again by itself, at once
/// after a normal end and after 1, 2, 4... up to 30 seconds after a failure.
/// Each time it opens, every topic is announced once, so whatever changed
/// while it was closed is read again.
class LiveChannel {
  LiveChannel({
    required this.dio,
    required this.live,
    this.path = '/events',
    this.onServerTopic,
    this.shortest = const Duration(seconds: 5),
  });

  final Dio dio;
  final LiveUpdates live;
  final String path;

  /// Told of each topic the server sends, and of every topic after each
  /// (re)connect: what the app does beyond reloading the screens.
  final void Function(LiveTopic topic)? onServerTopic;

  /// A stream that ends sooner than this counts as a failure, so a server
  /// that closes at once is not asked again in a tight loop.
  final Duration shortest;

  CancelToken? _cancel;
  StreamSubscription<String>? _lines;
  Timer? _retry;
  int _failures = 0;
  bool _running = false;

  /// How many times it has opened; for tests and logs.
  int opened = 0;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _retry?.cancel();
    _retry = null;
    _lines?.cancel();
    _lines = null;
    _cancel?.cancel();
    _cancel = null;
  }

  Future<void> _connect() async {
    if (!_running) return;
    final cancel = _cancel = CancelToken();
    final Response<ResponseBody> response;
    try {
      response = await dio.get<ResponseBody>(
        path,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: const {'Accept': 'text/event-stream'},
          // The server pings every 25 seconds: a minute of silence is a
          // connection that died without saying so (a phone gone offline).
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
    } catch (_) {
      if (_running && identical(cancel, _cancel)) _ended(failed: true);
      return;
    }
    if (!_running || !identical(cancel, _cancel)) return;

    opened++;
    final since = DateTime.now();
    // Whatever changed while it was closed.
    for (final topic in LiveTopic.values) {
      live.announce(topic);
      onServerTopic?.call(topic);
    }
    _lines = utf8.decoder
        .bind(response.data!.stream)
        .transform(const LineSplitter())
        .listen(
          _read,
          onError: (Object _) => _ended(failed: true),
          onDone: () =>
              _ended(failed: DateTime.now().difference(since) < shortest),
          cancelOnError: true,
        );
    _failures = 0;
  }

  void _read(String line) {
    // ": open", ": ping", blank lines and anything else are not changes.
    if (!line.startsWith('data:')) return;
    final Object? message;
    try {
      message = jsonDecode(line.substring(5).trim());
    } on FormatException {
      return;
    }
    if (message is! Map) return;
    final name = message['topic'];
    for (final topic in LiveTopic.values) {
      if (topic.name == name) {
        live.announce(topic);
        onServerTopic?.call(topic);
      }
    }
  }

  void _ended({required bool failed}) {
    _lines = null;
    _cancel = null;
    if (!_running) return;
    if (!failed) {
      _connect();
      return;
    }
    final wait = Duration(seconds: math.min(30, 1 << math.min(_failures, 5)));
    _failures++;
    _retry = Timer(wait, () {
      _retry = null;
      _connect();
    });
  }
}
