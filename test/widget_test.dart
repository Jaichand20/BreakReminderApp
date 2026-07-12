import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:squat_reminder/features/home/widgets/stat_tile.dart';
import 'package:squat_reminder/theme.dart';

void main() {
  testWidgets('StatTile shows its label (uppercased) and value',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: StatTile(label: 'Today', value: 42),
      ),
    ));

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('42', findRichText: true), findsOneWidget);
  });

  test('app theme uses the dark palette', () {
    final theme = buildAppTheme();
    expect(theme.scaffoldBackgroundColor, AppColors.pageBg);
    expect(theme.colorScheme.primary, AppColors.accent);
  });
}
