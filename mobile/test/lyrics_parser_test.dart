import 'package:adi_music/services/lyrics_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLrc', () {
    test('parses mm:ss.xx, mm:ss.xxx and mm:ss stamps', () {
      final lines = parseLrc('[00:01.50] one\n[00:02.250] two\n[01:03] three');
      expect(lines.map((l) => l.text), ['one', 'two', 'three']);
      expect(lines.map((l) => l.t), [1.5, 2.25, 63.0]);
    });

    test('expands multiple stamps on one line and sorts by time', () {
      final lines = parseLrc('[00:10.00][00:30.00] chorus\n[00:20.00] verse');
      expect(lines.map((l) => l.t), [10.0, 20.0, 30.0]);
      expect(lines.map((l) => l.text), ['chorus', 'verse', 'chorus']);
    });

    test('empty text becomes a note and untimed lines are dropped', () {
      final lines = parseLrc('[ar:Someone]\n[00:05.00]\nplain line');
      expect(lines, hasLength(1));
      expect(lines.single.text, '♪');
    });

    test('handles CRLF, null and empty input', () {
      expect(parseLrc('[00:01.00] a\r\n[00:02.00] b').map((l) => l.text), [
        'a',
        'b',
      ]);
      expect(parseLrc(null), isEmpty);
      expect(parseLrc(''), isEmpty);
    });
  });

  group('parseTtmlTime', () {
    test('supports every web-build format', () {
      expect(parseTtmlTime('27.395'), 27.395);
      expect(parseTtmlTime('27.395s'), 27.395);
      expect(parseTtmlTime('1234ms'), 1.234);
      expect(parseTtmlTime('3:14.571'), closeTo(194.571, 1e-9));
      expect(parseTtmlTime('00:03:14.571'), closeTo(194.571, 1e-9));
    });

    test('rejects garbage', () {
      expect(parseTtmlTime(null), isNull);
      expect(parseTtmlTime(''), isNull);
      expect(parseTtmlTime('abc'), isNull);
      expect(parseTtmlTime('1:2:3:4'), isNull);
    });
  });

  group('parseTtml', () {
    test('reads begin/end/dur, strips tags, decodes entities', () {
      const source = '''
<tt><body><div>
  <p begin="00:00:01.000" end="00:00:03.500"><span>Hello</span> &amp; <span>welcome</span></p>
  <p begin="5.0s" dur="2s">Second &quot;line&quot;</p>
  <p begin="nope">skipped</p>
  <p begin="9s"></p>
</div></body></tt>''';
      final lines = parseTtml(source);
      expect(lines, hasLength(3));
      expect(lines[0].text, 'Hello & welcome');
      expect(lines[0].t, 1.0);
      expect(lines[0].tEnd, 3.5);
      expect(lines[1].text, 'Second "line"');
      expect(lines[1].tEnd, 7.0);
      expect(lines[2].text, '♪');
    });
  });
}
