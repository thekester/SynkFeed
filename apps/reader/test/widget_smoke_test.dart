import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:synkfeed_reader/app/synkfeed_app.dart';

void main() {
  testWidgets('renders the SynkFeed shell', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    await tester.pumpWidget(
      SynkFeedApp(repository: MemoryLocalFeedRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('SynkFeed'), findsOneWidget);
    expect(find.text('Add feed'), findsOneWidget);
  });

  testWidgets('opens the account dialog from the sync button', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    await tester.pumpWidget(
      SynkFeedApp(repository: MemoryLocalFeedRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Connect to a sync server'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to a sync server'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });
}
