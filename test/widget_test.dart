import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:handy_ros/main.dart';
import 'package:handy_ros/services/app_settings.dart';

void main() {
  testWidgets('HandyROS boots to the home screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    await tester.pumpWidget(HandyROSApp(settings: settings));
    await tester.pump();

    // IndexedStack builds every tab at once, so the bottom nav's own
    // "Topics" label coexists with the Topics screen's own header —
    // both are expected now, not just one.
    expect(find.text('Topics'), findsWidgets);
    expect(find.text('/camera/image_raw'), findsOneWidget);
  });
}
