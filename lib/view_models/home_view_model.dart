import 'package:church_attendance_app/services/attendance_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_attendance_app/services/gps_service.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:church_attendance_app/services/notification_service.dart';

class HomeViewModel extends ChangeNotifier {
  final GPSService _gpsService = GPSService();
  final SupabaseService _supabaseService = SupabaseService();
  final NotificationService _notificationService = NotificationService();

  bool _isLocationEnabled = false;
  bool get isLocationEnabled => _isLocationEnabled;

  bool _isAttendanceChecked = false;
  bool get isAttendanceChecked => _isAttendanceChecked;

  bool _isBackgroundMonitoringEnabled = false;
  bool get isBackgroundMonitoringEnabled => _isBackgroundMonitoringEnabled;

  bool _isNotificationEnabled = false;
  bool get isNotificationEnabled => _isNotificationEnabled;

  String _statusMessage = '위치 서비스 준비 중...';
  String get statusMessage => _statusMessage;

  double _currentLatitude = 0.0;
  double get currentLatitude => _currentLatitude;

  double _currentLongitude = 0.0;
  double get currentLongitude => _currentLongitude;

  String _locationPermissionStatus = '확인 중...';
  String get locationPermissionStatus => _locationPermissionStatus;

  String _locationServiceStatus = '확인 중...';
  String get locationServiceStatus => _locationServiceStatus;

  HomeViewModel() {
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      _statusMessage = '서비스 초기화 중...';
      notifyListeners();

      await _supabaseService.init();
      await _notificationService.init();
      _gpsService.setAttendanceService(AttendanceService(_supabaseService));

      await _checkLocationStatus();
      await _getCurrentLocation();
      await _startLocationMonitoring();
      
      // 백그라운드 모니터링은 사용자 상호작용 시 시작
      // await toggleBackgroundMonitoring();

      _statusMessage = '초기화 완료 - 위치 서비스 준비됨';
      notifyListeners();
    } catch (e) {
      debugPrint('서비스 초기화 오류: $e');
      _statusMessage = '초기화 중 오류가 발생했습니다.';
      notifyListeners();
    }
  }

  Future<void> _checkLocationStatus() async {
    try {
      final permission = await _gpsService.checkLocationPermission();
      _locationPermissionStatus = _getPermissionStatusText(permission);

      final serviceEnabled = await _gpsService.isLocationServiceEnabled();
      _locationServiceStatus = serviceEnabled ? '활성화됨' : '비활성화됨';
      _isLocationEnabled =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (permission == LocationPermission.deniedForever) {
        _statusMessage = '위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.';
      } else if (permission == LocationPermission.denied) {
        _statusMessage = '위치 권한이 필요합니다. 권한을 허용해주세요.';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('위치 상태 확인 오류: $e');
      _locationPermissionStatus = '확인 실패';
      _locationServiceStatus = '확인 실패';
      notifyListeners();
    }
  }

  String _getPermissionStatusText(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
        return '항상 허용';
      case LocationPermission.whileInUse:
        return '앱 사용 중 허용';
      case LocationPermission.denied:
        return '거부됨';
      case LocationPermission.deniedForever:
        return '영구 거부됨';
      default:
        return '알 수 없음';
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      _statusMessage = '현재 위치 가져오는 중...';
      notifyListeners();

      final position = await _gpsService.getCurrentLocation();

      _currentLatitude = position.latitude;
      _currentLongitude = position.longitude;
      _statusMessage = '현재 위치 정보 업데이트됨';
      notifyListeners();
    } catch (e) {
      debugPrint('현재 위치 가져오기 오류: $e');
      _statusMessage = '위치 정보를 가져올 수 없습니다: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> requestLocationPermission() async {
    try {
      _statusMessage = '위치 권한 요청 중...';
      notifyListeners();

      final serviceEnabled = await _gpsService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _statusMessage = '위치 서비스가 비활성화되어 있습니다. 설정에서 위치 서비스를 켜주세요.';
        notifyListeners();
        return;
      }

      final permission = await Geolocator.requestPermission();

      await _checkLocationStatus();

      if (permission == LocationPermission.deniedForever) {
        _statusMessage = '위치 권한이 영구적으로 거부되었습니다. 설정 앱에서 권한을 허용해주세요.';
      } else if (permission == LocationPermission.denied) {
        _statusMessage = '위치 권한이 거부되었습니다. 다시 시도하거나 설정에서 허용해주세요.';
      } else {
        _statusMessage = '위치 권한이 허용되었습니다!';
        await _startLocationMonitoring();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('권한 요청 오류: $e');
      _statusMessage = '권한 요청 중 오류가 발생했습니다.';
      notifyListeners();
    }
  }

  Future<void> _startLocationMonitoring() async {
    try {
      await _gpsService.startLocationMonitoring();
      _gpsService.locationStatus.listen((isEnabled) {
        _isLocationEnabled = isEnabled;
        _statusMessage = isEnabled ? '위치 서비스 활성화됨 - 출석 체크 대기 중' : '위치 서비스 비활성화됨';
        notifyListeners();
      });
    } catch (e) {
      debugPrint('위치 모니터링 시작 오류: $e');
    }
  }

  Future<void> toggleBackgroundMonitoring() async {
    try {
      if (_isBackgroundMonitoringEnabled) {
        await _gpsService.stopBackgroundLocationMonitoring();
        _isBackgroundMonitoringEnabled = false;
        _statusMessage = '백그라운드 모니터링 중지됨';
      } else {
        await _gpsService.startBackgroundLocationMonitoring();
        _isBackgroundMonitoringEnabled = true;
        _statusMessage = '백그라운드 모니터링 시작됨 - 15분마다 위치 확인 (배터리 절약)';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('백그라운드 모니터링 토글 오류: $e');
      _statusMessage = '백그라운드 모니터링 설정 중 오류 발생';
      notifyListeners();
    }
  }

  Future<void> toggleNotifications() async {
    try {
      if (_isNotificationEnabled) {
        await _notificationService.cancelAllNotifications();
        _isNotificationEnabled = false;
        _statusMessage = '예배 알림이 취소되었습니다.';
      } else {
        await _notificationService.scheduleWeeklyWorshipNotifications();
        _isNotificationEnabled = true;
        _statusMessage = '주일 예배 알림이 설정되었습니다.';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('알림 설정 오류: $e');
      _statusMessage = '알림 설정 중 오류가 발생했습니다.';
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      if (_isBackgroundMonitoringEnabled) {
        await _gpsService.stopBackgroundLocationMonitoring();
      }
      if (_isNotificationEnabled) {
        await _notificationService.cancelAllNotifications();
      }
      _gpsService.stopLocationMonitoring();
      await _supabaseService.signOut();
    } catch (e) {
      debugPrint('로그아웃 오류: $e');
    }
  }

  Future<void> manualAttendanceCheck() async {
    try {
      final position = await _gpsService.getCurrentLocation();
      _currentLatitude = position.latitude;
      _currentLongitude = position.longitude;

      bool isWithinRadius = await _gpsService.isWithinChurchRadius(position);

      if (isWithinRadius) {
        try {
          final currentUser = _supabaseService.getCurrentUser();
          if (currentUser == null) {
            _statusMessage = '로그인이 필요합니다.';
            notifyListeners();
            return;
          }

          final currentService = await _supabaseService.getCurrentService();
          if (currentService == null) {
            _statusMessage = '현재 예배 서비스 정보를 찾을 수 없습니다.';
            notifyListeners();
            return;
          }

          final serviceId = currentService['id'].toString();
          final userId = currentUser.id;

          final existingRecord = await _supabaseService.checkAttendanceRecord(
            userId: userId,
            serviceId: serviceId,
          );

          if (existingRecord != null) {
            _statusMessage = '이미 출석 체크가 완료되었습니다.';
            _isAttendanceChecked = true;
            notifyListeners();
            return;
          }

          await _supabaseService.submitAttendanceCheck(
            latitude: position.latitude,
            longitude: position.longitude,
            userId: userId,
            serviceId: serviceId,
          );

          _statusMessage = '출석 체크 완료!';
          _isAttendanceChecked = true;
          notifyListeners();
        } catch (e) {
          debugPrint('출석 데이터 전송 오류: $e');
          _statusMessage = '출석 체크 중 오류가 발생했습니다.';
          notifyListeners();
        }
      } else {
        _statusMessage = '교회 범위 밖입니다. 교회 위치에서 80m 이내에 있어야 합니다.';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('수동 출석 체크 오류: $e');
      _statusMessage = '출석 체크 중 오류 발생';
      notifyListeners();
    }
  }
}
