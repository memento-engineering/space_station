import 'dart:io';

import 'package:args/args.dart';
import 'package:space_station_assets/src/space_delegate.dart';
import 'package:test/test.dart';

void main() {
  const gridHome = '/tmp/space-up-bind';

  ArgParser parser() {
    final parser = ArgParser();
    addSpaceStationFlags(parser, codedNames: const []);
    return parser;
  }

  SpaceStationConfig configFor(List<String> arguments) =>
      spaceStationConfigFrom(
        parser().parse(['--grid-home', gridHome, ...arguments]),
        codedNames: const {},
      )!;

  test('help documents and accepted bind forms', () {
    final usage = parser().usage;
    expect(
      usage,
      allOf(
        contains('--bind=<address>'),
        contains('`lan`'),
        contains('0.0.0.0'),
        contains('InternetAddress.anyIPv4'),
        contains('IPv4 literal'),
        contains('Absent: loopback (InternetAddress.loopbackIPv4)'),
      ),
    );

    expect(configFor(const []).controlAddress, isNull);
    expect(
      configFor(const ['--bind', 'lan']).controlAddress,
      same(InternetAddress.anyIPv4),
    );

    final literal = configFor(const ['--bind', '192.0.2.44']).controlAddress;
    expect(literal, isNotNull);
    expect(literal!.address, '192.0.2.44');
    expect(literal.type, InternetAddressType.IPv4);
  });

  test('invalid bind values refuse loudly', () {
    for (final value in const ['', 'localhost', '::1']) {
      expect(
        () => configFor(['--bind', value]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'space up: --bind "$value" must be "lan" or an IPv4 literal.',
          ),
        ),
      );
    }
  });
}
