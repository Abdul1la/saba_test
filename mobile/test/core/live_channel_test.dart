// M8: the server's live changes, `GET /events`, read by the app. Against a
// fake connection: what it announces, and how it opens again.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saba_marketplace/core/network/live_channel.dart';
import 'package:saba_marketplace/core/network/live_updates.dart';

/// A server with a stream the test writes to, or one that refuses.
class _Server implements HttpClientAdapter {
  final List<StreamController<Uint8List>> streams = [];
  final List<RequestOptions> asked = [];
  bool refuse = false;

  StreamController<Uint8List> get current => streams.last;

  void send(String text) => current.add(Uint8List.fromList(utf8.encode(text)));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    if (refuse) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final stream = StreamController<Uint8List>();
    streams.add(stream);
    return ResponseBody(
      stream.stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Server server;
  late LiveUpdates live;
  late List<LiveTopic> heard;
  late LiveChannel channel;

  setUp(() {
    server = _Server();
    live = LiveUpdates();
    heard = [];
    live.changes.listen(heard.add);
    channel = LiveChannel(
      dio: Dio(BaseOptions(baseUrl: 'http://saba.test/api/v1'))
        ..httpClientAdapter = server,
      live: live,
      shortest: Duration.zero,
    );
  });
  tearDown(() {
    channel.stop();
    live.dispose();
  });

  Future<void> tick([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// Waits for [ok], polling: a fixed wait was too short once the whole
  /// suite ran at the same time.
  Future<void> until(bool Function() ok, {int ms = 5000}) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (!ok() && DateTime.now().isBefore(end)) {
      await tick(10);
    }
  }

  test('each change is announced; comments and other topics are not', () async {
    channel.start();
    await until(() => heard.length == LiveTopic.values.length);
    expect(server.asked.single.path, '/events');
    expect(server.asked.single.headers['Accept'], 'text/event-stream');
    // Opened: everything once, for what changed while it was closed.
    expect(heard, LiveTopic.values);
    heard.clear();

    server.send(': open\n\n');
    server.send('data: {"topic":"orders","id":"12"}\n\n');
    server.send(': ping\n\n');
    server.send('data: {"topic":"bills"}\n\n');
    server.send('data: not json\n\n');
    // One change may arrive in two pieces.
    server.send('data: {"topic":"notif');
    server.send('ications"}\n\n');
    await until(() => heard.length >= 2);
    await tick(50);
    expect(heard, [LiveTopic.orders, LiveTopic.notifications]);
  });

  test(
    'a stream that ends opens again at once, and reloads everything',
    () async {
      channel.start();
      await until(() => channel.opened == 1);
      heard.clear();
      await server.current.close();
      await until(() => heard.length == LiveTopic.values.length);
      expect(server.asked, hasLength(2), reason: 'it did not open again');
      expect(heard, LiveTopic.values);
    },
  );

  test(
    'after failures it waits 1, then 2 seconds; stopped, it asks no more',
    () async {
      server.refuse = true;
      final began = DateTime.now();
      channel.start();
      await until(() => server.asked.length == 2);
      expect(server.asked, hasLength(2), reason: 'not asked again');
      expect(
        DateTime.now().difference(began).inMilliseconds,
        greaterThanOrEqualTo(950),
        reason: 'asked again before 1 s',
      );
      server.refuse = false;
      final again = DateTime.now();
      await until(() => channel.opened == 1);
      expect(server.asked, hasLength(3));
      expect(
        DateTime.now().difference(again).inMilliseconds,
        greaterThanOrEqualTo(1900),
        reason: 'asked again before 2 s',
      );

      channel.stop();
      await server.current.close();
      await tick(1200);
      expect(server.asked, hasLength(3), reason: 'asked again after stopping');
    },
  );

  test('a server that closes at once is not asked in a tight loop', () async {
    final strict = LiveChannel(
      dio: Dio(BaseOptions(baseUrl: 'http://saba.test/api/v1'))
        ..httpClientAdapter = server,
      live: live,
    );
    addTearDown(strict.stop);
    strict.start();
    await until(() => strict.opened == 1);
    await server.current.close();
    await tick(300);
    expect(server.asked, hasLength(1), reason: 'asked again at once');
    await until(() => server.asked.length == 2);
    expect(server.asked, hasLength(2));
  });
}
