import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart'; 

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

  // polling interval in seconds (start at 20)
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
    WakelockPlus.enable(); // Prevents screen sleep
    _startForegroundTask();
    _ensureLocationPermissionAndStartTimer();
  }

  // Initialize and start foreground service (kept from your code)
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
          name: 'launcher', // uses app icon
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
    );
  }

  // Request permission and start the timer
  Future<void> _ensureLocationPermissionAndStartTimer() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
      // Permission not granted - just print and do not start
      print('Location permission denied. Please enable in settings.');
      return;
    }

    // Also ensure location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled. Please enable them.');
      return;
    }

    _startLocationTimer(); // start periodic location printing
  }

  void _startLocationTimer() {
    // Cancel existing, if any
    _locationTimer?.cancel();

    // Start a new periodic timer using current interval
    _locationTimer = Timer.periodic(Duration(seconds: _intervalSeconds), (timer) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
        print('[Location Poll] ${DateTime.now().toIso8601String()} -> '
            'lat: ${pos.latitude}, lon: ${pos.longitude}, accuracy: ${pos.accuracy}');
      } catch (e) {
        print('Failed to get location: $e');
      }
    });

    // Immediately print once (optional; keeps first print without waiting full interval)
    _printOneLocationNow();
  }

  Future<void> _printOneLocationNow() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      print('[Immediate Location] ${DateTime.now().toIso8601String()} -> '
          'lat: ${pos.latitude}, lon: ${pos.longitude}, accuracy: ${pos.accuracy}');
    } catch (e) {
      print('Immediate location read failed: $e');
    }
  }

  // ✅ Stop service and exit app
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

  // The Accept action: change polling interval from 20 -> 5
  void _onAcceptPressed() {
    if (_intervalSeconds == 5) {
      print('Already in 5-second mode.');
      return;
    }

    setState(() {
      _intervalSeconds = 5;
    });

    // Restart timer with new interval
    if (_locationTimer != null) {
      print('Accept pressed: switching interval to 5 seconds.');
      _startLocationTimer();
    } else {
      // If timer not running (maybe permissions not granted earlier), ensure permissions then start.
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
            // Accept button (placed in AppBar actions)
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
