import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

class UpdateService {
  // Replace with your specific GitHub API endpoint
  static const String _repoUrl = 'https://api.github.com/repos/Cleverfix-labs/Racingpad/releases/latest';

  static Future<void> checkAndApplyUpdate() async {
    try {
      // 1. Get the current app version from pubspec.yaml
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., "1.0.0"

      // 2. Fetch latest release data from GitHub
      final response = await http.get(Uri.parse(_repoUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['tag_name'].replaceAll('v', ''); // Cleans "v1.0.1" to "1.0.1"
        
        // Find the APK asset in the release list
        final downloadUrl = data['assets'][0]['browser_download_url'];

        // 3. Compare versions
        if (_isNewer(latestVersion, currentVersion)) {
          print("Update Found! Current: $currentVersion, New: $latestVersion");
          _executeUpdate(downloadUrl);
        } else {
          print("App is up to date (Version: $currentVersion)");
        }
      }
    } catch (e) {
      print("Update check error: $e");
    }
  }

  // Simple version comparison logic
  static bool _isNewer(String latest, String current) {
    List<int> latestParts = latest.split('.').map(int.parse).toList();
    List<int> currentParts = current.split('.').map(int.parse).toList();
    
    for (var i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static void _executeUpdate(String url) {
    try {
      // Triggers download and opens Android installer intent
      OtaUpdate().execute(
        url,
        destinationFilename: 'racingpad_update.apk',
      ).listen((OtaEvent event) {
        print('Update status: ${event.status} : ${event.value}%');
      });
    } catch (e) {
      print('OTA Update failed: $e');
    }
  }
}