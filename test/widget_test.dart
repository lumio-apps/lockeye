import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockeye/core/app_state.dart';
import 'package:lockeye/core/format.dart';
import 'package:lockeye/core/models.dart';
import 'package:lockeye/core/pin_hasher.dart';
import 'package:lockeye/services/phone_lock_service.dart';
import 'package:lockeye/services/update_service.dart';

void main() {
  group('PinHasher', () {
    test('accepts the right PIN and rejects a wrong one', () {
      final stored = PinHasher.create('1234');
      expect(PinHasher.verify('1234', stored), isTrue);
      expect(PinHasher.verify('4321', stored), isFalse);
    });

    test('does not store the PIN and uses a new salt each time', () {
      final a = PinHasher.create('1234');
      final b = PinHasher.create('1234');
      expect(a.contains('1234'), isFalse);
      expect(a, isNot(equals(b)));
      expect(PinHasher.verify('1234', b), isTrue);
    });

    test('rejects broken stored values', () {
      expect(PinHasher.verify('1234', ''), isFalse);
      expect(PinHasher.verify('1234', 'nonsense'), isFalse);
    });
  });

  group('UpdateService.isNewer', () {
    test('compares versions', () {
      expect(UpdateService.isNewer('1.2.0', '1.1.9'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.1', '1.1.0'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '1.9.9+4'), isTrue);
    });
  });

  group('UpdateService.describeError', () {
    test('explains network problems', () {
      expect(UpdateService.describeError(const SocketException('x')), contains('Could not reach GitHub'));
    });

    test('falls back to a generic message', () {
      expect(UpdateService.describeError(StateError('x')), contains('Could not check'));
    });
  });

  group('formatWhen', () {
    final now = DateTime(2026, 10, 29, 22, 0);

    test('today and yesterday', () {
      expect(formatWhen(DateTime(2026, 10, 29, 21, 47), now: now), 'Today, 21:47');
      expect(formatWhen(DateTime(2026, 10, 28, 8, 12), now: now), 'Yesterday, 08:12');
    });

    test('this week and older', () {
      expect(formatWhen(DateTime(2026, 10, 26, 23, 30), now: now), 'Mon, 23:30');
      expect(formatWhen(DateTime(2026, 10, 20, 9, 5), now: now), '20 Oct 2026, 09:05');
    });
  });

  group('formatSize', () {
    test('formats bytes', () {
      expect(formatSize(512), '512 B');
      expect(formatSize(2048), '2 KB');
      expect(formatSize(5 * 1024 * 1024), '5.0 MB');
    });
  });

  group('PendingShot.parseLines', () {
    test('reads lines, skips broken ones, oldest first', () {
      const text = '{"time": 2000, "attempt": 2, "path": "/a/b.jpg"}\n'
          'not json\n'
          '\n'
          '{"time": 1000, "attempt": 1, "path": null}\n'
          '{"attempt": 3}\n';
      final shots = PendingShot.parseLines(text);
      expect(shots.length, 2);
      expect(shots[0].timeMs, 1000);
      expect(shots[0].path, isNull);
      expect(shots[1].attempt, 2);
      expect(shots[1].path, '/a/b.jpg');
    });

    test('empty text gives no shots', () {
      expect(PendingShot.parseLines(''), isEmpty);
    });
  });

  group('IntruderEntry', () {
    test('keeps its source and defaults old entries to the app', () {
      const phone = IntruderEntry(
        id: 'p1',
        path: null,
        timeMs: 5,
        attempt: 0,
        source: kSourcePhone,
      );
      final back = IntruderEntry.fromJson(phone.toJson());
      expect(back.isPhone, isTrue);
      expect(back.isTest, isTrue);

      final old = IntruderEntry.fromJson({'id': 'x', 'path': null, 'time': 1, 'attempt': 2});
      expect(old.source, kSourceApp);
      expect(old.isPhone, isFalse);
    });
  });

  group('IntruderEntry tamper', () {
    test('attempt -1 on the phone source means the guard was switched off', () {
      const entry = IntruderEntry(id: 't', path: null, timeMs: 1, attempt: -1, source: kSourcePhone);
      expect(entry.isTamper, isTrue);
      expect(entry.isTest, isFalse);
    });
  });

  group('remainingLockMs', () {
    test('counts down with the uptime clock', () {
      expect(remainingLockMs(durationMs: 30000, setAt: 1000, now: 1000), 30000);
      expect(remainingLockMs(durationMs: 30000, setAt: 1000, now: 11000), 20000);
      expect(remainingLockMs(durationMs: 30000, setAt: 1000, now: 31000), 0);
      expect(remainingLockMs(durationMs: 30000, setAt: 1000, now: 99000), 0);
    });

    test('a restart (clock went back) starts the lockout again', () {
      expect(remainingLockMs(durationMs: 60000, setAt: 500000, now: 4000), 60000);
    });

    test('no lockout stored means no wait', () {
      expect(remainingLockMs(durationMs: 0, setAt: 0, now: 5), 0);
    });
  });

  group('isWeakPin', () {
    test('rejects repeats and simple runs', () {
      expect(isWeakPin('000000'), isTrue);
      expect(isWeakPin('111111'), isTrue);
      expect(isWeakPin('123456'), isTrue);
      expect(isWeakPin('654321'), isTrue);
      expect(isWeakPin('345678'), isTrue);
    });

    test('accepts ordinary PINs', () {
      expect(isWeakPin('482915'), isFalse);
      expect(isWeakPin('120120'), isFalse);
    });
  });
}
