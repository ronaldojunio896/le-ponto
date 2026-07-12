import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> currentPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Permissao de localizacao negada.');
    }
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw Exception('GPS desligado.');
    const settings = LocationSettings(accuracy: LocationAccuracy.high);
    return Geolocator.getCurrentPosition(locationSettings: settings);
  }

  Stream<Position> positionStream({int distanceFilter = 20}) async* {
    await currentPosition();
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );
    yield* Geolocator.getPositionStream(locationSettings: settings);
  }

  double distanceMeters({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    return Geolocator.distanceBetween(
      fromLatitude,
      fromLongitude,
      toLatitude,
      toLongitude,
    );
  }
}
