import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:space_station_assets/space_station_assets.dart';
import 'package:test/test.dart';

final class _ByteConsumer implements StreamConsumer<List<int>> {
  final _bytes = <int>[];

  String get text => utf8.decode(_bytes);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

final class _RecordingStdout implements Stdout {
  _RecordingStdout() : _consumer = _ByteConsumer() {
    _sink = IOSink(_consumer);
  }

  final _ByteConsumer _consumer;
  late final IOSink _sink;

  String get text => _consumer.text;

  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  String lineTerminator = '\n';
  @override
  Future<void> get done => _sink.done;
  @override
  bool get hasTerminal => false;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  IOSink get nonBlocking => _sink;
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> flush() => _sink.flush();
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
}

Future<String> _primeOutput(CommandRunner<int> Function() build) async {
  final home = Directory.systemTemp.createTempSync('space-prime-composition-');
  final output = _RecordingStdout();
  try {
    final code = await IOOverrides.runZoned(
      () => build().run(const ['prime']),
      getCurrentDirectory: () => home,
      stdout: () => output,
    );
    expect(code, 0);
    await output.flush();
    return output.text;
  } finally {
    await output.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  }
}

void main() {
  test('downstream runner invocation reaches prime output', () async {
    final output = await _primeOutput(
      () =>
          buildRunner(name: 'lunar', runnerInvocation: 'dart run lunar:lunar'),
    );

    expect(
      const LineSplitter().convert(output),
      contains('Invoke: dart run lunar:lunar prime [--hook-json]'),
    );
  });

  test('space default runner invocation reaches prime output', () async {
    final output = await _primeOutput(() => buildRunner());

    expect(
      const LineSplitter().convert(output),
      contains('Invoke: dart run space:space prime [--hook-json]'),
    );
  });
}
