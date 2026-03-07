import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the NotificationService
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  final Random _rng = Random();

  // Decoy notification texts to hide the real message content
  static const List<Map<String, String>> _decoys = [
    {'title': 'System Service', 'body': 'Background battery optimization completed.'},
    {'title': 'Weather Update', 'body': 'Checking local weather data...'},
    {'title': 'System UI', 'body': 'Keyboard layout updated successfully.'},
    {'title': 'Device Care', 'body': 'Storage scan completed. 0 threats found.'},
    {'title': 'Network Sync', 'body': 'Synchronizing timezone data.'},
  ];

  Future<void> init() async {
    if (_isInitialized) return;

    // Default Android init (requires app icon 'ic_launcher' in drawable)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Default iOS init
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true);

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
    _isInitialized = true;
  }

  /// Displays a "Masked" notification.
  /// Regardless of the actual [realSender] or [realMessage], 
  /// the OS will only display a harmless decoy string securely.
  Future<void> showMaskedNotification() async {
    if (!_isInitialized) await init();

    final decoy = _decoys[_rng.nextInt(_decoys.length)];

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'chimera_sys_channel', 
      'System Services',
      channelDescription: 'Core system background services',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: false,
    );
    
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails();
        
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      id: _rng.nextInt(100000), // Random ID
      title: decoy['title'],
      body: decoy['body'],
      notificationDetails: platformChannelSpecifics,
    );
  }
}
