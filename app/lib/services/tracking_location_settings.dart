import 'package:geolocator/geolocator.dart';

/// Keep platform-specific options compatible with both Flutter toolchains.
LocationSettings trackingLocationSettings(String operatingSystem) {
  if (operatingSystem == 'ios' || operatingSystem == 'macos') {
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 4,
      activityType: ActivityType.fitness,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
      pauseLocationUpdatesAutomatically: false,
    );
  }
  if (operatingSystem == 'ohos') return const _OhosTrackingSettings();
  return const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 4,
  );
}

class _OhosTrackingSettings extends LocationSettings {
  const _OhosTrackingSettings()
    : super(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 4,
        // The native plugin can swallow subscription errors. A silent stream
        // must time out so RunTracker displays an error and reconnects.
        timeLimit: const Duration(seconds: 30),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    // geolocator_ohos expects milliseconds and divides by 1000 for LocationKit.
    // Omitting this key leaves the pinned plugin's default at 10,000 seconds.
    // Use the wire option directly because the main toolchain has no OhosSettings.
    ..['timeInterval'] = 1000;
}
