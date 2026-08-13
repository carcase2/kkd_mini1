import 'package:discipline_tracker/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldDeliverMissedCompletion', () {
    final end = DateTime(2026, 8, 13, 10, 0);

    test('does not fire before the target time', () {
      expect(
        shouldDeliverMissedCompletion(
          endTime: end,
          now: end.subtract(const Duration(seconds: 1)),
          alreadyShown: false,
          alreadyVisibleOrPending: false,
        ),
        isFalse,
      );
    });

    test('waits for the OS scheduled notification during grace', () {
      expect(
        shouldDeliverMissedCompletion(
          endTime: end,
          now: end.add(const Duration(seconds: 5)),
          alreadyShown: false,
          alreadyVisibleOrPending: false,
        ),
        isFalse,
      );
    });

    test('fires after grace if nothing was shown', () {
      expect(
        shouldDeliverMissedCompletion(
          endTime: end,
          now: end.add(const Duration(seconds: 21)),
          alreadyShown: false,
          alreadyVisibleOrPending: false,
        ),
        isTrue,
      );
    });

    test('does not fire if already shown', () {
      expect(
        shouldDeliverMissedCompletion(
          endTime: end,
          now: end.add(const Duration(minutes: 10)),
          alreadyShown: true,
          alreadyVisibleOrPending: false,
        ),
        isFalse,
      );
    });

    test('does not fire if OS notification is pending or in the tray', () {
      expect(
        shouldDeliverMissedCompletion(
          endTime: end,
          now: end.add(const Duration(minutes: 10)),
          alreadyShown: false,
          alreadyVisibleOrPending: true,
        ),
        isFalse,
      );
    });
  });
}
