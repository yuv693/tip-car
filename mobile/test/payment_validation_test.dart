import 'package:flutter_test/flutter_test.dart';
import 'package:tip_car_bus/utils/payment_validation.dart';

void main() {
  group('isValidUpiVpa', () {
    test('accepts common UPI handles without a dot', () {
      expect(isValidUpiVpa('9876543210@ybl'), isTrue);
      expect(isValidUpiVpa('name@okaxis'), isTrue);
      expect(isValidUpiVpa('first.last@oksbi'), isTrue);
    });

    test('trims surrounding whitespace', () {
      expect(isValidUpiVpa('  user@okicici  '), isTrue);
    });

    test('rejects malformed VPA values', () {
      expect(isValidUpiVpa(''), isFalse);
      expect(isValidUpiVpa('not-a-vpa'), isFalse);
      expect(isValidUpiVpa('user@@ybl'), isFalse);
      expect(isValidUpiVpa('user @ybl'), isFalse);
      expect(isValidUpiVpa('@ybl'), isFalse);
    });
  });
}
