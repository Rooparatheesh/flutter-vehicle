import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

// Background task entry point
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

/// Background location handler
class LocationTaskHandler extends TaskHandler {
  Timer? _timer;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    debugPrint('Background task started at $timestamp');

    _timer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
        debugPrint(
          '[BG Location] ${DateTime.now()} -> lat: ${pos.latitude}, lon: ${pos.longitude}, acc: ${pos.accuracy}',
        );
      } catch (e) {
        debugPrint('BG location error: $e');
      }
    });
  }

  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    _timer?.cancel();
    debugPrint('Background task stopped.');
  }

  void onButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
  
  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // TODO: implement onRepeatEvent
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme:
          ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const PlainScreen(),
    );
  }
}

class PlainScreen extends StatefulWidget {
  const PlainScreen({super.key});

  @override
  State<PlainScreen> createState() => _PlainScreenState();
}

class _PlainScreenState extends State<PlainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _iconsDisabled = false;
  int _intervalSeconds = 20;
  Timer? _locationTimer;

  final List<Map<String, dynamic>> _pages = [
    {'title': 'Home', 'icon': CupertinoIcons.home, 'color': Colors.deepPurple},
    {'title': 'Map', 'icon': CupertinoIcons.map, 'color': Colors.blue},
    {'title': 'Travel', 'icon': CupertinoIcons.airplane, 'color': Colors.orange},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // prevent sleep
    _startForegroundTask();
    _ensureLocationPermissionAndStartTimer();
  }

  Future<void> _startForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_channel',
        channelName: 'Foreground Service',
        channelDescription: 'Keeps the app active in background',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        iconData: NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 10000,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    await FlutterForegroundTask.startService(
      notificationTitle: 'App Active',
      notificationText: 'App is running in the foreground service',
      callback: startCallback, //  background tracking
    );
  }

  Future<void> _ensureLocationPermissionAndStartTimer() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (kDebugMode) {
        print('Location permission denied. Please enable in settings.');
      }
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (kDebugMode) {
        print('Location services are disabled. Please enable them.');
      }
      return;
    }

    _startLocationTimer();
  }

  void _startLocationTimer() {
    _locationTimer?.cancel();

    _locationTimer =
        Timer.periodic(Duration(seconds: _intervalSeconds), (timer) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
        if (kDebugMode) {
          print('[Location Poll] ${DateTime.now().toIso8601String()} -> '
              'lat: ${pos.latitude}, lon: ${pos.longitude}, accuracy: ${pos.accuracy}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Failed to get location: $e');
        }
      }
    });

    _printOneLocationNow();
  }

  Future<void> _printOneLocationNow() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      if (kDebugMode) {
        print('[Immediate Location] ${DateTime.now().toIso8601String()} -> '
            'lat: ${pos.latitude}, lon: ${pos.longitude}, accuracy: ${pos.accuracy}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Immediate location read failed: $e');
      }
    }
  }

  void _exitApp() async {
    await FlutterForegroundTask.stopService();
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else if (Platform.isIOS) {
      exit(0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.stopService();
    _locationTimer?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_iconsDisabled && index != 1) return;
    setState(() {
      _selectedIndex = index;
      if (index == 1) _iconsDisabled = true;
    });
  }

  Future<bool> _onWillPop() async => false;

  void _onAcceptPressed() {
    if (_intervalSeconds == 5) {
      if (kDebugMode) {
        print('Already in 5-second mode.');
      }
      return;
    }

    setState(() {
      _intervalSeconds = 5;
    });

    if (_locationTimer != null) {
      print('Accept pressed: switching interval to 5 seconds.');
      _startLocationTimer();
    } else {
      _ensureLocationPermissionAndStartTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_pages[_selectedIndex]['title']),
          backgroundColor: _pages[_selectedIndex]['color'],
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: _onAcceptPressed,
              child: const Text(
                'Accept',
                style: TextStyle(color: Colors.white),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Exit App'),
                    content: const Text('Do you want to close the app?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _exitApp();
                        },
                        child: const Text('Exit'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_pages[_selectedIndex]['icon'],
                  size: 80, color: _pages[_selectedIndex]['color']),
              const SizedBox(height: 20),
              Text(
                _pages[_selectedIndex]['title'],
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _pages[_selectedIndex]['color']),
              ),
              const SizedBox(height: 12),
              Text('Current polling interval: $_intervalSeconds seconds',
                  style: const TextStyle(fontSize: 16)),
              if (_iconsDisabled)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text(
                    "Icons disabled after Map selected",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_pages.length, (index) {
                final isSelected = _selectedIndex == index;
                final isDisabled = _iconsDisabled && index != 1;
                return GestureDetector(
                  onTap: isDisabled ? null : () => _onItemTapped(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _pages[index]['color'].withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _pages[index]['icon'],
                      size: 30,
                      color: isDisabled
                          ? Colors.grey.withOpacity(0.4)
                          : isSelected
                              ? _pages[index]['color']
                              : Colors.grey,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
