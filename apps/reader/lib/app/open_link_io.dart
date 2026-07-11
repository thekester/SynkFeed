import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser or matching application.
void openExternalUrl(Uri url) {
  launchUrl(url, mode: LaunchMode.externalApplication);
}
