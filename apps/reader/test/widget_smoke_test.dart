import 'package:flutter_test/flutter_test.dart';
import 'package:synkfeed_reader/app/synkfeed_app.dart';

void main() {
  testWidgets('renders the SynkFeed shell', (tester) async {
    await tester.pumpWidget(const SynkFeedApp());
    await tester.pumpAndSettle();

    expect(find.text('SynkFeed'), findsOneWidget);
    expect(find.text('Add feed'), findsOneWidget);
  });
}
