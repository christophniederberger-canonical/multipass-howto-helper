import 'package:flutter/foundation.dart';

class OriginValidator {
  const OriginValidator();

  bool isAllowed(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null) {
      return false;
    }

    if (kDebugMode && (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      return true;
    }

    return uri.host == 'ubuntu.com' ||
        uri.host.endsWith('.ubuntu.com') ||
        uri.host == 'canonical.com' ||
        uri.host.endsWith('.canonical.com');
  }
}
