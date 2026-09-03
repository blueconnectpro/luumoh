import 'dart:convert';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

class MapboxPoint {
  const MapboxPoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

class MapboxAddressResult {
  const MapboxAddressResult({
    required this.name,
    required this.address,
    required this.point,
    this.place,
  });

  final String name;
  final String address;
  final MapboxPoint point;
  final String? place;
}

class MapboxRouteEstimate {
  const MapboxRouteEstimate({
    required this.distanceMeters,
    required this.durationSeconds,
    this.geometry = const [],
  });

  final double distanceMeters;
  final double durationSeconds;
  final List<MapboxPoint> geometry;

  double get distanceKm => distanceMeters / 1000;
  int get durationMinutes => (durationSeconds / 60).ceil();
}

class MapboxLocationService {
  const MapboxLocationService(this.accessToken);

  final String accessToken;

  bool get isConfigured => accessToken.trim().isNotEmpty;

  Future<MapboxAddressResult?> reverseGeocode(MapboxPoint point) async {
    _assertConfigured();
    if (!point.isValid) {
      throw ArgumentError.value(point, 'point', 'Invalid coordinates');
    }

    final uri = Uri.https(
      'api.mapbox.com',
      '/search/geocode/v6/reverse',
      {
        'longitude': point.longitude.toString(),
        'latitude': point.latitude.toString(),
        'language': 'en',
        'limit': '1',
        'access_token': accessToken,
      },
    );
    final body = await _getJson(uri);
    return _parseFirstAddress(body);
  }

  Future<List<MapboxAddressResult>> searchAddresses(
    String query, {
    MapboxPoint? proximity,
    int limit = 5,
    String? country,
  }) async {
    _assertConfigured();
    final normalized = query.trim();
    if (normalized.length < 3) {
      return const [];
    }

    final params = <String, String>{
      'q': normalized,
      'language': 'en',
      'autocomplete': 'true',
      'limit': limit.clamp(1, 10).toString(),
      'access_token': accessToken,
    };
    if (country != null && country.trim().isNotEmpty) {
      params['country'] = country.trim();
    }
    if (proximity != null && proximity.isValid) {
      params['proximity'] = '${proximity.longitude},${proximity.latitude}';
    }

    final uri =
        Uri.https('api.mapbox.com', '/search/geocode/v6/forward', params);
    final body = await _getJson(uri);
    final features = body['features'];
    if (features is! List) {
      return const [];
    }

    return features
        .whereType<Map<String, dynamic>>()
        .map(_addressFromFeature)
        .whereType<MapboxAddressResult>()
        .toList();
  }

  Future<MapboxRouteEstimate?> routeEstimate({
    required MapboxPoint origin,
    required MapboxPoint destination,
    String profile = 'mapbox/driving-traffic',
  }) async {
    _assertConfigured();
    if (!origin.isValid || !destination.isValid) {
      return null;
    }

    final coordinates =
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/$profile/$coordinates',
      {
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'simplified',
        'steps': 'false',
        'access_token': accessToken,
      },
    );
    final body = await _getJson(uri);
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) {
      return null;
    }
    final route = routes.first;
    if (route is! Map<String, dynamic>) {
      return null;
    }
    return MapboxRouteEstimate(
      distanceMeters: (route['distance'] as num? ?? 0).toDouble(),
      durationSeconds: (route['duration'] as num? ?? 0).toDouble(),
      geometry: _routeGeometry(route),
    );
  }

  Uri navigationUri({
    MapboxPoint? origin,
    required MapboxPoint destination,
    String? destinationName,
  }) {
    final query = <String, String>{
      'destination': '${destination.longitude},${destination.latitude}',
      if (destinationName != null && destinationName.trim().isNotEmpty)
        'destination_name': destinationName.trim(),
      if (origin != null && origin.isValid)
        'origin': '${origin.longitude},${origin.latitude}',
    };
    return Uri.https('www.mapbox.com', '/directions/', query);
  }

  Future<MapboxPoint> currentPoint() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('Location services are disabled on this device.');
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      throw StateError('Location permission is required.');
    }

    final position = await geo.Geolocator.getCurrentPosition(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final point = MapboxPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (_looksLikeDefaultCaliforniaEmulatorPoint(point)) {
      final lastKnown = await geo.Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final lastKnownPoint = MapboxPoint(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
        );
        if (!_looksLikeDefaultCaliforniaEmulatorPoint(lastKnownPoint)) {
          return lastKnownPoint;
        }
      }
      throw StateError(
        'Device GPS is reporting the emulator default location in California. '
        'Set the emulator/device location, then try GPS again.',
      );
    }
    return point;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map<String, dynamic>
          ? body['message'] ?? body['error'] ?? response.reasonPhrase
          : response.reasonPhrase;
      throw StateError('Mapbox request failed: $message');
    }
    if (body is! Map<String, dynamic>) {
      throw StateError('Mapbox returned an invalid response.');
    }
    return body;
  }

  MapboxAddressResult? _parseFirstAddress(Map<String, dynamic> body) {
    final features = body['features'];
    if (features is! List || features.isEmpty) {
      return null;
    }
    final feature = features.first;
    if (feature is! Map<String, dynamic>) {
      return null;
    }
    return _addressFromFeature(feature);
  }

  MapboxAddressResult? _addressFromFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map<String, dynamic> ||
        properties is! Map<String, dynamic>) {
      return null;
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) {
      return null;
    }
    final longitude = (coordinates[0] as num?)?.toDouble();
    final latitude = (coordinates[1] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      return null;
    }

    final name = properties['name'] as String? ??
        properties['full_address'] as String? ??
        'Selected address';
    final place = properties['place_formatted'] as String?;
    final address = properties['full_address'] as String? ??
        [
          properties['name'] as String?,
          place,
        ]
            .whereType<String>()
            .where((part) => part.trim().isNotEmpty)
            .join(', ');

    if (address.trim().isEmpty) {
      return null;
    }

    return MapboxAddressResult(
      name: name,
      address: address,
      place: place,
      point: MapboxPoint(latitude: latitude, longitude: longitude),
    );
  }

  List<MapboxPoint> _routeGeometry(Map<String, dynamic> route) {
    final geometry = route['geometry'];
    if (geometry is! Map<String, dynamic>) {
      return const [];
    }
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) {
      return const [];
    }
    return coordinates
        .whereType<List>()
        .map((coordinate) {
          if (coordinate.length < 2) {
            return null;
          }
          final longitude = (coordinate[0] as num?)?.toDouble();
          final latitude = (coordinate[1] as num?)?.toDouble();
          if (latitude == null || longitude == null) {
            return null;
          }
          final point = MapboxPoint(latitude: latitude, longitude: longitude);
          return point.isValid ? point : null;
        })
        .whereType<MapboxPoint>()
        .toList(growable: false);
  }

  void _assertConfigured() {
    if (!isConfigured) {
      throw StateError('MAPBOX_ACCESS_TOKEN is not configured.');
    }
  }
}

bool _looksLikeDefaultCaliforniaEmulatorPoint(MapboxPoint point) {
  return point.latitude >= 36.8 &&
      point.latitude <= 38.2 &&
      point.longitude >= -123.0 &&
      point.longitude <= -121.0;
}
