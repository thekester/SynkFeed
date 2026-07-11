import 'package:synkfeed_core/synkfeed_core.dart';

/// Non-web fallback; the app uses [FileSessionStore] on desktop and mobile,
/// so this variant only exists to satisfy the conditional import.
SessionStore createWebSessionStore() => MemorySessionStore();
