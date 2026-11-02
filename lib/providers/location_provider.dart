import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:cosmetix/database/store_data.dart';

/// A geographic position.
typedef GeoPoint = ({double lat, double lng});

/// Reads the device position; replaced by a fake in tests.
typedef LocationFetcher = Future<GeoPoint?> Function();

/// Where the user is, to show distances to shops. The position never leaves
/// the phone. Until the user allows the location (or when it is not available)
/// distances are counted from the city centre and the screens say so.
class LocationProvider extends ChangeNotifier {
  LocationProvider({LocationFetcher? fetcher})
    : _fetcher = fetcher ?? _deviceLocation;

  final LocationFetcher _fetcher;

  GeoPoint? _position;
  bool _loading = false;
  bool _asked = false;

  /// The real position, or null.
  GeoPoint? get position => _position;

  /// True once a real position is known.
  bool get isReal => _position != null;
  bool get loading => _loading;

  /// The user was asked and the answer was no (or the position is unknown).
  bool get unavailable => _asked && _position == null && !_loading;

  /// Where distances are counted from.
  GeoPoint get origin =>
      _position ?? (lat: StoreData.centerLat, lng: StoreData.centerLng);

  int distanceTo(double lat, double lng) =>
      StoreData.meters(origin.lat, origin.lng, lat, lng);

  /// Asks for the position (the system shows its permission dialog once).
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      _position = await _fetcher();
    } catch (e) {
      debugPrint('location failed: $e');
      _position = null;
    }
    _asked = true;
    _loading = false;
    notifyListeners();
  }

  static Future<GeoPoint?> _deviceLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (lat: p.latitude, lng: p.longitude);
  }
}
