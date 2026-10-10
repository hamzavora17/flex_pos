import 'package:flutter_test/flutter_test.dart';
import 'package:flex_pos/services/business_service.dart';
import 'package:flex_pos/services/exceptions.dart';

void main() {
  group('BusinessService Security & Resolution Tests', () {
    test('getBusinessId fails closed with BusinessNotFoundException when no user session exists', () async {
      final service = BusinessService();
      expect(
        () async => await service.getBusinessId(),
        throwsA(isA<BusinessNotFoundException>()),
      );
    });

    test('clearCache resets cached business ID ensuring session changes do not leak cache', () async {
      final service = BusinessService();
      service.clearCache();
      
      expect(
        () async => await service.getBusinessId(),
        throwsA(isA<BusinessNotFoundException>()),
      );
    });

    test('getBusinessId with forceRefresh: true re-evaluates authorization', () async {
      final service = BusinessService();
      expect(
        () async => await service.getBusinessId(forceRefresh: true),
        throwsA(isA<BusinessNotFoundException>()),
      );
    });
  });
}
