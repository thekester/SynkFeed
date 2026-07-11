import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:synkfeed_reader/app/synkfeed_app.dart';

void main() {
  testWidgets('renders the SynkFeed shell', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    await tester.pumpWidget(const SynkFeedApp());
    await tester.pumpAndSettle();

    expect(find.text('SynkFeed'), findsOneWidget);
    expect(find.text('Add feed'), findsOneWidget);
  });
}
