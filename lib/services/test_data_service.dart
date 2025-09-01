import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:flutter/foundation.dart';

class TestDataService {
  final SupabaseService _supabaseService;

  TestDataService(this._supabaseService);

  Future<Map<String, dynamic>?> createTestService(String date) async {
    try {
      debugPrint('테스트용 예배 서비스 생성 시작: $date');

      final now = DateTime.now();

      final serviceData = {
        'service_date': date,
        'start_time': '10:00:00',
        'end_time': '12:00:00',
        'created_at': now.toIso8601String(),
      };

      final response = await _supabaseService.client
          .from('services')
          .insert(serviceData)
          .select()
          .single();

      debugPrint('테스트용 예배 서비스 생성 성공: ${response['id']}');

      await _createTestLocation(response['id'] as int);

      return response;
    } catch (e) {
      debugPrint('테스트용 예배 서비스 생성 오류: $e');
      return null;
    }
  }

  Future<void> _createTestLocation(int serviceId) async {
    try {
      debugPrint('테스트용 교회 위치 정보 생성 시작: $serviceId');

      const churchLatitude = 36.4255072;
      const churchLongitude = 127.3995609;

      final locationData = {
        'service_id': serviceId,
        'latitude': churchLatitude,
        'longitude': churchLongitude,
        'radius_meters': 80,
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabaseService.client.from('locations').insert(locationData);

      debugPrint('테스트용 교회 위치 정보 생성 성공');
    } catch (e) {
      debugPrint('테스트용 교회 위치 정보 생성 오류: $e');
    }
  }
}
