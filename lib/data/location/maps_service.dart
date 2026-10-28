import 'package:url_launcher/url_launcher.dart';

typedef MapCoordinates = ({double latitude, double longitude});

/// A venue pin never includes the student's position. A walking route does.
abstract interface class MapsService {
  Future<bool> openPlace(MapCoordinates destination);

  Future<bool> openWalkingRoute({
    required MapCoordinates origin,
    required MapCoordinates destination,
  });
}

/// Universal HTTPS links open the Maps app when available, or a browser.
class GoogleMapsService implements MapsService {
  const GoogleMapsService();

  static String _point(MapCoordinates point) =>
      '${point.latitude},${point.longitude}';

  static Uri placeUrl(MapCoordinates destination) => Uri.https(
    'www.google.com',
    '/maps/search/',
    {'api': '1', 'query': _point(destination)},
  );

  static Uri walkingRouteUrl({
    required MapCoordinates origin,
    required MapCoordinates destination,
  }) => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': _point(origin),
    'destination': _point(destination),
    'travelmode': 'walking',
  });

  @override
  Future<bool> openPlace(MapCoordinates destination) =>
      launchUrl(placeUrl(destination), mode: LaunchMode.externalApplication);

  @override
  Future<bool> openWalkingRoute({
    required MapCoordinates origin,
    required MapCoordinates destination,
  }) => launchUrl(
    walkingRouteUrl(origin: origin, destination: destination),
    mode: LaunchMode.externalApplication,
  );
}
