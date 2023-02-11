import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:background_location_tracker/background_location_tracker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

import 'package:background_location_tracker/src/channel/foreground_channel.dart';
@pragma('vm:entry-point')
void backgroundCallback() {
  BackgroundLocationTrackerManager.handleBackgroundUpdated(
       (data) async => Repo().update(data),
  );
}
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {

  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance)
  {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }
  int counter=0;
  WidgetsFlutterBinding.ensureInitialized();
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance)
    {

        if (counter==1)  /// turn off gps  5s
          {
            await BackgroundLocationTrackerManager.stopTracking();
          }
        if (counter==6)  /// turn on gps  5s
          {
          await BackgroundLocationTrackerManager.startTracking();
          }
        if (counter==11) counter =0;
        print('counter : $counter');
        counter++;

        ///-----------Notification update ------------------------------------
        List<String> locationList = await  LocationDao().getLocations();

        bool isTrack = await BackgroundLocationTrackerManager.isTracking();
        String gpsStatus='Checking Tracker';
        if (isTrack) {gpsStatus ='Tracker is ON';} else{gpsStatus ='Tracker is OFF';}

        flutterLocalNotificationsPlugin.show(
          notificationId,
          '$notificationTitle ${DateTime.now().toString()}' ,
          'List_Length:${locationList.length} -- $gpsStatus',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              notificationChannelId,
              notificationTitle,
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );
        ///--------------------------------------------------------------------
      }
  });
}


const notificationChannelId = 'Background_task';
const notificationId = 123;
const notificationTitle = 'Recording GPS';

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();
  /// ------------Initialize Background Location Tracker
  await BackgroundLocationTrackerManager.initialize(
    backgroundCallback,
    config: const BackgroundLocationTrackerConfig(
      loggingEnabled: true,
      androidConfig: AndroidConfig(
        notificationIcon: 'explore',
        trackingInterval: Duration(milliseconds: 500),
        distanceFilterMeters: null,
      ),
      iOSConfig: IOSConfig(
        activityType: ActivityType.FITNESS,
        distanceFilterMeters: null,
        restartAfterKill: true,
      ),
    ),
  );
  ///---------------------------------------------
  ///----------------- ADD notification chanel
  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    notificationTitle, // title
    description:
    'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);


  /// ----------------- end ADD notification chanel

  /// ------------Initialize Background Service
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,

      notificationChannelId: notificationChannelId,
      initialNotificationTitle: notificationTitle,
      // initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      // onBackground: onIosBackground,
    ),
  );
  service.startService();

  ///---------------------------------------------
  runApp(MyApp());
}

@override
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var isTracking = false;
  int _lens=0;
  Timer? _timer;
  String _gpsStatus='Checking Tracker';
  @override
  void initState() {
    super.initState();
    BackgroundLocationTrackerManager.startTracking();
    _startLocationsUpdatesStream();

  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Container(
          width: double.infinity,
          child: Column(
            children: [
                      Text('Location List Length : $_lens'),
                      Text(_gpsStatus),
                      ElevatedButton(
                      onPressed:() async {
                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        prefs.reload();
                        if (prefs.containsKey(LocationDao._locationsKey))
                        {
                          prefs.remove(LocationDao._locationsKey);
                        }},
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text('Clear Location List'),
                      ),
                      ElevatedButton(
                      onPressed:() async {
                        final service = FlutterBackgroundService();
                        await service.startService();
                        await BackgroundLocationTrackerManager.startTracking();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text('Start background services'),
                      ),
                      ElevatedButton(
                      onPressed:() async {
                      final service = FlutterBackgroundService();
                      service.invoke("stopService");
                      await BackgroundLocationTrackerManager.stopTracking();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Stop background services'),
                      )
                  ]


          ),
        ),
      ),
    );
  }

  Future<void> _getTrackingStatus() async {
    isTracking = await BackgroundLocationTrackerManager.isTracking();
    setState(() {});
  }


  void _startLocationsUpdatesStream() {
    _timer?.cancel();
    List<String> locationList=[];
    _timer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
          locationList= await LocationDao().getLocations();
          _lens = locationList.length;
          await _getTrackingStatus();
          if (isTracking) {_gpsStatus ='Tracker is ON';} else{_gpsStatus ='Tracker is OFF';}
          setState(() {});

    });
  }
}

class Repo {
  static Repo? _instance;

  Repo._();

  factory Repo() => _instance ??= Repo._();

  Future<void> update(BackgroundLocationUpdateData data) async {
    final text = 'Location Update: Lat: ${data.lat} Lon: ${data.lon}';
    print(text); // ignore: avoid_print
    await LocationDao().saveLocation(data);
  }
}

class LocationDao {
  static const _locationsKey = 'background_updated_locations';
  static const _locationSeparator = '-/-/-/';

  static LocationDao? _instance;

  LocationDao._();

  factory LocationDao() => _instance ??= LocationDao._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> saveLocation(BackgroundLocationUpdateData data) async {
    final locations = await getLocations();
    locations.add(
        '${DateTime.now().toIso8601String()}       ${data.lat},${data.lon}');
    await (await prefs)
        .setString(_locationsKey, locations.join(_locationSeparator));
  }

  Future<List<String>> getLocations() async {
    final prefs = await this.prefs;
    await prefs.reload();
    final locationsString = prefs.getString(_locationsKey);
    if (locationsString == null) return [];
    return locationsString.split(_locationSeparator);
  }

  Future<void> clear() async => (await prefs).clear();
}
