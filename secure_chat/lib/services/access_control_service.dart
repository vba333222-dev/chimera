import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ntp/ntp.dart';

class AccessDeniedException implements Exception {
  final String message;
  AccessDeniedException(this.message);
  @override
  String toString() => message;
}

class AccessControlService {
  // Koordinat Markas Besar (HQ) fiktif, contoh Jakarta Pusat
  static const double hqLatitude = -6.200000;
  static const double hqLongitude = 106.816666;
  
  // Radius maksimal (dalam meter) yang diizinkan dari HQ
  static const double allowedRadiusMeters = 500.0;

  // Jam Kerja (misal: 08:00 - 18:00)
  static const int workHourStart = 8;
  static const int workHourEnd = 18;

  Future<void> verifyAccess() async {
    await _verifyLocation();
    await _verifyTime();
  }

  Future<void> _verifyLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Cek apakah service lokasi menyala
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw AccessDeniedException('Location services are disabled. Access denied.');
    }

    // Cek dan request permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw AccessDeniedException('Location permissions are denied. Access denied.');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw AccessDeniedException('Location permissions are permanently denied, we cannot request permissions. Access denied.');
    }

    // Ambil lokasi saat ini (akurasi tinggi)
    final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));

    // Hitung jarak dari HQ
    final distance = Geolocator.distanceBetween(
      hqLatitude, hqLongitude,
      position.latitude, position.longitude,
    );

    if (distance > allowedRadiusMeters) {
      throw AccessDeniedException('Device is outside the authorized geofence radius. Access denied.');
    }
  }

  Future<void> _verifyTime() async {
    try {
      // Ambil waktu dari Network Time Protocol (NTP)
      final ntpTime = await NTP.now();
      final localTime = ntpTime.toLocal();

      // Cek apakah di luar jam kerja (misalnya sebelum jam 8 pagi atau sesudah jam 6 sore)
      if (localTime.hour < workHourStart || localTime.hour >= workHourEnd) {
        throw AccessDeniedException('Outside authorized operational hours. Service is locked.');
      }
    } catch (e) {
      if (e is AccessDeniedException) {
        rethrow;
      }
      // Jika gagal menghubungi NTP (misalnya offline), jatuhkan fallback ke keamanan ketat
      throw AccessDeniedException('Failed to verify network time. Ensure you have an active internet connection.');
    }
  }
}

final accessControlServiceProvider = Provider<AccessControlService>((ref) {
  return AccessControlService();
});
