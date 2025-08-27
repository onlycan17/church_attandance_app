import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) {
      debugPrint('알림 서비스가 이미 초기화되었습니다.');
      return;
    }

    try {
      // 알림 초기화 설정
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      );

      // Android 채널 설정
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'attendance_channel',
        '출석 체크 알림',
        description: '교회 출석 체크 관련 알림',
        importance: Importance.high,
        playSound: true,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      _isInitialized = true;
      debugPrint('알림 서비스 초기화 성공');
    } catch (e) {
      debugPrint('알림 서비스 초기화 오류: $e');
      rethrow;
    }
  }

  // 알림 응답 처리
  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    debugPrint('알림 클릭됨: ${response.payload}');
    // 알림 클릭 시 특정 동작 수행 가능
  }

  // 즉시 알림 표시
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // 초기화되지 않았다면 초기화
    if (!_isInitialized) {
      debugPrint('알림 서비스가 초기화되지 않았습니다. 초기화 중...');
      await init();
    }

    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'attendance_channel',
        '출석 체크 알림',
        channelDescription: '교회 출석 체크 관련 알림',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // 예배 시간 알림 예약
  Future<void> scheduleWorshipNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    // 초기화되지 않았다면 초기화
    if (!_isInitialized) {
      debugPrint('알림 서비스가 초기화되지 않았습니다. 초기화 중...');
      await init();
    }

    final tz.TZDateTime tzScheduledDate = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'attendance_channel',
        '출석 체크 알림',
        channelDescription: '교회 출석 체크 관련 알림',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      scheduledDate.millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      tzScheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  // 주일 예배 알림 설정 (매주 일요일)
  Future<void> scheduleWeeklyWorshipNotifications() async {
    final now = DateTime.now();
    final kstOffset = const Duration(hours: 9); // KST 시간대
    final kstNow = now.add(kstOffset);

    // 이번 주 일요일 찾기
    final daysUntilSunday = (7 - kstNow.weekday) % 7;
    final nextSunday = kstNow.add(
      Duration(days: daysUntilSunday == 0 ? 7 : daysUntilSunday),
    );

    // 주일 예배 시간들 (KST)
    final worshipTimes = [
      const TimeOfDay(hour: 10, minute: 30), // 1부 예배
      const TimeOfDay(hour: 14, minute: 0), // 2부 예배
    ];

    for (final worshipTime in worshipTimes) {
      final scheduledDate = DateTime(
        nextSunday.year,
        nextSunday.month,
        nextSunday.day,
        worshipTime.hour,
        worshipTime.minute,
      ).subtract(kstOffset); // UTC로 변환

      // 예배 30분 전 알림
      final reminderTime = scheduledDate.subtract(const Duration(minutes: 30));

      if (reminderTime.isAfter(now)) {
        final hour = worshipTime.hour > 12
            ? worshipTime.hour - 12
            : (worshipTime.hour == 0 ? 12 : worshipTime.hour);
        final period = worshipTime.hour >= 12 ? '오후' : '오전';
        final minute = worshipTime.minute.toString().padLeft(2, '0');
        final timeString = '$period $hour:$minute';

        await scheduleWorshipNotification(
          title: '⛪ 예배 출석 체크',
          body: '$timeString 예배가 곧 시작됩니다. 출석 체크를 해주세요!',
          scheduledDate: reminderTime,
          payload: 'worship_reminder_${worshipTime.hour}_${worshipTime.minute}',
        );
      }
    }
  }

  // 초기화 상태 확인
  bool get isInitialized => _isInitialized;

  // 모든 예약된 알림 취소
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) {
      debugPrint('알림 서비스가 초기화되지 않았습니다.');
      return;
    }
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  // 특정 알림 취소
  Future<void> cancelNotification(int id) async {
    if (!_isInitialized) {
      debugPrint('알림 서비스가 초기화되지 않았습니다.');
      return;
    }
    await _flutterLocalNotificationsPlugin.cancel(id);
  }
}
