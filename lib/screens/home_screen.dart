import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_attendance_app/services/gps_service.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:church_attendance_app/services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GPSService _gpsService = GPSService();
  final SupabaseService _supabaseService = SupabaseService();
  final NotificationService _notificationService = NotificationService();

  bool _isLocationEnabled = false;
  bool _isAttendanceChecked = false;
  bool _isBackgroundMonitoringEnabled = false;
  bool _isNotificationEnabled = false;
  String _statusMessage = '위치 서비스 준비 중...';
  double _currentLatitude = 0.0;
  double _currentLongitude = 0.0;
  String _locationPermissionStatus = '확인 중...';
  String _locationServiceStatus = '확인 중...';

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      setState(() {
        _statusMessage = '서비스 초기화 중...';
      });

      // Supabase 초기화
      await _supabaseService.init();

      // NotificationService 초기화
      await _notificationService.init();

      // GPSService에 SupabaseService 주입
      _gpsService.setSupabaseService(_supabaseService);

      // 위치 권한 및 서비스 상태 확인
      await _checkLocationStatus();

      // 현재 위치 정보 가져오기
      await _getCurrentLocation();

      // 위치 서비스 시작
      _startLocationMonitoring();

      setState(() {
        _statusMessage = '초기화 완료 - 위치 서비스 준비됨';
      });
    } catch (e) {
      debugPrint('서비스 초기화 오류: $e');
      setState(() {
        _statusMessage = '초기화 중 오류가 발생했습니다.';
      });
    }
  }

  Future<void> _checkLocationStatus() async {
    try {
      // 위치 권한 상태 확인
      final permission = await _gpsService.checkLocationPermission();
      setState(() {
        _locationPermissionStatus = _getPermissionStatusText(permission);
      });

      // 위치 서비스 상태 확인
      final serviceEnabled = await _gpsService.isLocationServiceEnabled();
      setState(() {
        _locationServiceStatus = serviceEnabled ? '활성화됨' : '비활성화됨';
        _isLocationEnabled =
            permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
      });

      debugPrint('위치 권한 상태: $permission');
      debugPrint('위치 서비스 상태: $serviceEnabled');

      // 권한이 거부되었을 경우 사용자 안내
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage = '위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.';
        });
      } else if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage = '위치 권한이 필요합니다. 권한을 허용해주세요.';
        });
      }
    } catch (e) {
      debugPrint('위치 상태 확인 오류: $e');
      setState(() {
        _locationPermissionStatus = '확인 실패';
        _locationServiceStatus = '확인 실패';
      });
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

  Color _getPermissionColor(String permissionStatus) {
    switch (permissionStatus) {
      case '항상 허용':
      case '앱 사용 중 허용':
        return Colors.green;
      case '거부됨':
      case '영구 거부됨':
        return Colors.red;
      case '확인 실패':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _statusMessage = '현재 위치 가져오는 중...';
      });

      final position = await _gpsService.getCurrentLocation();

      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
        _statusMessage = '현재 위치 정보 업데이트됨';
      });

      debugPrint(
        '홈 화면: 현재 위치 - 위도: ${position.latitude}, 경도: ${position.longitude}',
      );
    } catch (e) {
      debugPrint('현재 위치 가져오기 오류: $e');
      setState(() {
        _statusMessage = '위치 정보를 가져올 수 없습니다: ${e.toString()}';
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      setState(() {
        _statusMessage = '위치 권한 요청 중...';
      });

      // 위치 서비스 활성화 확인
      final serviceEnabled = await _gpsService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _statusMessage = '위치 서비스가 비활성화되어 있습니다. 설정에서 위치 서비스를 켜주세요.';
        });
        return;
      }

      // 권한 요청
      final permission = await Geolocator.requestPermission();

      // 권한 상태 다시 확인
      await _checkLocationStatus();

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage = '위치 권한이 영구적으로 거부되었습니다. 설정 앱에서 권한을 허용해주세요.';
        });
      } else if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage = '위치 권한이 거부되었습니다. 다시 시도하거나 설정에서 허용해주세요.';
        });
      } else {
        setState(() {
          _statusMessage = '위치 권한이 허용되었습니다!';
        });
        // 권한 허용 시 위치 모니터링 시작
        await _startLocationMonitoring();
      }
    } catch (e) {
      debugPrint('권한 요청 오류: $e');
      setState(() {
        _statusMessage = '권한 요청 중 오류가 발생했습니다.';
      });
    }
  }

  Future<void> _openAppSettings() async {
    try {
      final uri = Uri.parse('app-settings:');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        setState(() {
          _statusMessage = '설정 앱을 열 수 없습니다. 수동으로 설정에서 위치 권한을 허용해주세요.';
        });
      }
    } catch (e) {
      debugPrint('설정 앱 열기 오류: $e');
      setState(() {
        _statusMessage = '설정 앱을 열 수 없습니다. 수동으로 설정에서 위치 권한을 허용해주세요.';
      });
    }
  }

  Future<void> _startLocationMonitoring() async {
    try {
      _gpsService.startLocationMonitoring();

      // 위치 상태 스트림 구독
      _gpsService.locationStatus.listen((isEnabled) {
        setState(() {
          _isLocationEnabled = isEnabled;
          _statusMessage = isEnabled
              ? '위치 서비스 활성화됨 - 출석 체크 대기 중'
              : '위치 서비스 비활성화됨';
        });
      });
    } catch (e) {
      debugPrint('위치 모니터링 시작 오류: $e');
    }
  }

  Future<void> _toggleBackgroundMonitoring() async {
    try {
      if (_isBackgroundMonitoringEnabled) {
        await _gpsService.stopBackgroundLocationMonitoring();
        setState(() {
          _isBackgroundMonitoringEnabled = false;
          _statusMessage = '백그라운드 모니터링 중지됨';
        });
      } else {
        await _gpsService.startBackgroundLocationMonitoring();
        setState(() {
          _isBackgroundMonitoringEnabled = true;
          _statusMessage = '백그라운드 모니터링 시작됨 - 15분마다 위치 확인 (배터리 절약)';
        });
      }
    } catch (e) {
      debugPrint('백그라운드 모니터링 토글 오류: $e');
      setState(() {
        _statusMessage = '백그라운드 모니터링 설정 중 오류 발생';
      });
    }
  }

  Future<void> _toggleNotifications() async {
    try {
      if (_isNotificationEnabled) {
        await _notificationService.cancelAllNotifications();
        setState(() {
          _isNotificationEnabled = false;
          _statusMessage = '예배 알림이 취소되었습니다.';
        });
      } else {
        await _notificationService.scheduleWeeklyWorshipNotifications();
        setState(() {
          _isNotificationEnabled = true;
          _statusMessage = '주일 예배 알림이 설정되었습니다.';
        });
      }
    } catch (e) {
      debugPrint('알림 설정 오류: $e');
      setState(() {
        _statusMessage = '알림 설정 중 오류가 발생했습니다.';
      });
    }
  }

  Future<void> _logout() async {
    try {
      // 백그라운드 모니터링 중지
      if (_isBackgroundMonitoringEnabled) {
        await _gpsService.stopBackgroundLocationMonitoring();
      }

      // 알림 취소
      if (_isNotificationEnabled) {
        await _notificationService.cancelAllNotifications();
      }

      // 위치 서비스 중지
      _gpsService.stopLocationMonitoring();

      // Supabase 로그아웃
      await _supabaseService.signOut();

      // 로그인 화면으로 이동
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      debugPrint('로그아웃 오류: $e');
      // 오류가 발생해도 로그인 화면으로 이동
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⛪ 교회 출석 체크'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 환영 메시지
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade100,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.waving_hand,
                      color: Colors.orange.shade500,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '안녕하세요!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          Text(
                            '오늘도 예배 출석 체크를 시작하세요',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 상태 정보 카드
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '현재 상태',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildStatusRow(
                      Icons.location_on,
                      '위치 서비스',
                      _isLocationEnabled ? '활성화됨' : '비활성화됨',
                      _isLocationEnabled ? Colors.green : Colors.red,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.security,
                      '위치 권한',
                      _locationPermissionStatus,
                      _getPermissionColor(_locationPermissionStatus),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.gps_fixed,
                      'GPS 서비스',
                      _locationServiceStatus,
                      _locationServiceStatus == '활성화됨'
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.check_circle,
                      '출석 체크',
                      _isAttendanceChecked ? '완료됨' : '대기 중',
                      _isAttendanceChecked ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.access_time,
                      '백그라운드 모니터링',
                      _isBackgroundMonitoringEnabled ? '실행 중' : '중지됨',
                      _isBackgroundMonitoringEnabled
                          ? Colors.green
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.notifications,
                      '예배 알림',
                      _isNotificationEnabled ? '설정됨' : '미설정',
                      _isNotificationEnabled ? Colors.green : Colors.grey,
                    ),
                    if (_statusMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.message,
                              color: Colors.blue.shade600,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage,
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 현재 위치 정보
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '현재 위치',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _getCurrentLocation,
                            tooltip: '위치 새로고침',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_currentLatitude != 0.0 &&
                          _currentLongitude != 0.0) ...[
                        Text('위도: $_currentLatitude'),
                        Text('경도: $_currentLongitude'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '위치 정보 획득됨',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ] else ...[
                        const Text('위치 정보 없음'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '새로고침 버튼을 눌러 위치를 가져오세요',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 권한 요청 버튼 (권한이 거부되었을 경우)
              if (_locationPermissionStatus == '거부됨' ||
                  _locationPermissionStatus == '영구 거부됨')
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.location_off,
                              color: Colors.red.shade600,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '위치 권한이 필요합니다',
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _locationPermissionStatus == '영구 거부됨'
                                  ? '설정 앱에서 위치 권한을 허용해주세요.'
                                  : '아래 버튼을 눌러 권한을 허용해주세요.',
                              style: TextStyle(
                                color: Colors.red.shade600,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      if (_locationPermissionStatus == '영구 거부됨')
                        Column(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _openAppSettings,
                              icon: const Icon(Icons.settings),
                              label: const Text('설정에서 권한 허용하기'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '설정 앱이 열리지 않으면 수동으로 설정하세요',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _requestLocationPermission,
                          icon: const Icon(Icons.location_on),
                          label: const Text('위치 권한 허용하기'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),

              // 출석 체크 버튼
              Center(
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLocationEnabled
                          ? () => _manualAttendanceCheck()
                          : null,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('수동 출석 체크'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isLocationEnabled
                          ? () => _toggleBackgroundMonitoring()
                          : null,
                      icon: Icon(
                        _isBackgroundMonitoringEnabled
                            ? Icons.stop
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        _isBackgroundMonitoringEnabled
                            ? '백그라운드 모니터링 중지'
                            : '백그라운드 모니터링 시작',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isBackgroundMonitoringEnabled
                            ? Colors.red
                            : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _toggleNotifications(),
                      icon: Icon(
                        _isNotificationEnabled
                            ? Icons.notifications_off
                            : Icons.notifications,
                      ),
                      label: Text(
                        _isNotificationEnabled ? '예배 알림 취소' : '예배 알림 설정',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isNotificationEnabled
                            ? Colors.orange
                            : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 테스트 정보
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '테스트 정보',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('• 10초 간격으로 위치 수집 (배터리 절약)'),
                      const Text('• 15분마다 백그라운드에서 위치 확인'),
                      const Text('• 교회 위치에서 80m 이내일 경우 자동 출석 체크'),
                      const Text('• GPS 위치 정보는 Supabase에 전송됩니다'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manualAttendanceCheck() async {
    try {
      // 현재 위치 가져오기
      final position = await _gpsService.getCurrentLocation();

      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
      });

      // 출석 체크 로직 실행
      bool isWithinRadius = await _gpsService.isWithinChurchRadius(position);

      if (isWithinRadius) {
        try {
          // 현재 사용자 확인
          final currentUser = _supabaseService.getCurrentUser();
          if (currentUser == null) {
            setState(() {
              _statusMessage = '로그인이 필요합니다.';
            });
            return;
          }

          // 현재 예배 서비스 정보 가져오기
          final currentService = await _supabaseService.getCurrentService();
          if (currentService == null) {
            setState(() {
              _statusMessage = '현재 예배 서비스 정보를 찾을 수 없습니다.';
            });
            return;
          }

          final serviceId = currentService['id'].toString();
          final userId = currentUser.id;

          // 이미 출석 체크했는지 확인
          final existingRecord = await _supabaseService.checkAttendanceRecord(
            userId: userId,
            serviceId: serviceId,
          );

          if (existingRecord != null) {
            setState(() {
              _statusMessage = '이미 출석 체크가 완료되었습니다.';
              _isAttendanceChecked = true;
            });
            return;
          }

          // 출석 데이터 전송
          await _supabaseService.submitAttendanceCheck(
            latitude: position.latitude,
            longitude: position.longitude,
            userId: userId,
            serviceId: serviceId,
          );

          setState(() {
            _statusMessage = '출석 체크 완료!';
            _isAttendanceChecked = true;
          });

          debugPrint(
            '수동 출석 체크 성공 - 위치: ${position.latitude}, ${position.longitude}',
          );
        } catch (e) {
          debugPrint('출석 데이터 전송 오류: $e');
          setState(() {
            _statusMessage = '출석 체크 중 오류가 발생했습니다.';
          });
        }
      } else {
        setState(() {
          _statusMessage = '교회 범위 밖입니다. 교회 위치에서 80m 이내에 있어야 합니다.';
        });
      }
    } catch (e) {
      debugPrint('수동 출석 체크 오류: $e');
      setState(() {
        _statusMessage = '출석 체크 중 오류 발생';
      });
    }
  }

  Widget _buildStatusRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
