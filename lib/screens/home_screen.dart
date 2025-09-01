import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:church_attendance_app/view_models/home_view_model.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: const _HomeScreenContent(),
    );
  }
}

class _HomeScreenContent extends StatelessWidget {
  const _HomeScreenContent();

  Future<void> _openAppSettings() async {
    try {
      final uri = Uri.parse('app-settings:');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('설정 앱 열기 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<HomeViewModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('⛪ 교회 출석 체크'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await viewModel.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
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
                      viewModel.isLocationEnabled ? '활성화됨' : '비활성화됨',
                      viewModel.isLocationEnabled ? Colors.green : Colors.red,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.security,
                      '위치 권한',
                      viewModel.locationPermissionStatus,
                      _getPermissionColor(viewModel.locationPermissionStatus),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.gps_fixed,
                      'GPS 서비스',
                      viewModel.locationServiceStatus,
                      viewModel.locationServiceStatus == '활성화됨'
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.check_circle,
                      '출석 체크',
                      viewModel.isAttendanceChecked ? '완료됨' : '대기 중',
                      viewModel.isAttendanceChecked ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.access_time,
                      '백그라운드 모니터링',
                      viewModel.isBackgroundMonitoringEnabled ? '실행 중' : '중지됨',
                      viewModel.isBackgroundMonitoringEnabled
                          ? Colors.green
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      Icons.notifications,
                      '예배 알림',
                      viewModel.isNotificationEnabled ? '설정됨' : '미설정',
                      viewModel.isNotificationEnabled ? Colors.green : Colors.grey,
                    ),
                    if (viewModel.statusMessage.isNotEmpty) ...[
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
                                viewModel.statusMessage,
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
                            onPressed: () => viewModel.manualAttendanceCheck(),
                            tooltip: '위치 새로고침',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (viewModel.currentLatitude != 0.0 &&
                          viewModel.currentLongitude != 0.0) ...[
                        Text('위도: ${viewModel.currentLatitude}'),
                        Text('경도: ${viewModel.currentLongitude}'),
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
              if (viewModel.locationPermissionStatus == '거부됨' ||
                  viewModel.locationPermissionStatus == '영구 거부됨')
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
                              viewModel.locationPermissionStatus == '영구 거부됨'
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
                      if (viewModel.locationPermissionStatus == '영구 거부됨')
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
                          onPressed: () => viewModel.requestLocationPermission(),
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
              Center(
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: viewModel.isLocationEnabled
                          ? () => viewModel.manualAttendanceCheck()
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
                      onPressed: viewModel.isLocationEnabled
                          ? () => viewModel.toggleBackgroundMonitoring()
                          : null,
                      icon: Icon(
                        viewModel.isBackgroundMonitoringEnabled
                            ? Icons.stop
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        viewModel.isBackgroundMonitoringEnabled
                            ? '백그라운드 모니터링 중지'
                            : '백그라운드 모니터링 시작',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: viewModel.isBackgroundMonitoringEnabled
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
                      onPressed: () => viewModel.toggleNotifications(),
                      icon: Icon(
                        viewModel.isNotificationEnabled
                            ? Icons.notifications_off
                            : Icons.notifications,
                      ),
                      label: Text(
                        viewModel.isNotificationEnabled ? '예배 알림 취소' : '예배 알림 설정',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: viewModel.isNotificationEnabled
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
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
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
}