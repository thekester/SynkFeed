import 'package:web/web.dart' as web;

/// Opens [url] in a new tab.
///
/// Calls `window.open` synchronously so the browser still sees the user's
/// click as the trigger; routing through url_launcher adds an async hop that
/// popup blockers reject.
void openExternalUrl(Uri url) {
  web.window.open(url.toString(), '_blank', 'noopener,noreferrer');
}
