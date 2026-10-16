import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_space_flutter/vibe_space_flutter.dart';

void main() {
  test('untrusted views cannot inject widgets, HTML, duplicate input IDs or deep trees', () {
    for (final view in [
      {'type': 'html', 'html': '<script>alert(1)</script>'},
      {'type': 'progress', 'value': double.nan},
      {
        'type': 'column',
        'children': [
          {'type': 'input', 'id': 'x', 'label': 'X'},
          {'type': 'input', 'id': 'x', 'label': 'X'},
        ],
      },
    ]) {
      expect(() => validateVibeView(view), throwsFormatException);
    }
    Map<String, dynamic> deep = {'type': 'text', 'text': 'x'};
    for (var i = 0; i < 18; i++) {
      deep = {
        'type': 'column',
        'children': [deep],
      };
    }
    expect(() => validateVibeView(deep), throwsFormatException);
  });
  testWidgets(
    'declarative view renders and dispatches host callbacks at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? command, input;
      final view = <String, dynamic>{
        'type': 'card',
        'children': [
          {'type': 'heading', 'text': 'Mini-app'},
          {'type': 'text', 'text': '<script>literal text</script>'},
          {'type': 'input', 'id': 'name', 'label': 'Name'},
          {
            'type': 'row',
            'children': [
              {'type': 'action', 'title': 'Apply', 'command': 'apply'},
            ],
          },
        ],
      };
      validateVibeView(view);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VibeView(
                value: view,
                onCommand: (name, args) => command = name,
                onInput: (key, value) => input = value,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Vibe');
      await tester.tap(find.text('Apply'));
      expect(command, 'apply');
      expect(input, 'Vibe');
      expect(tester.takeException(), isNull);
      expect(find.text('<script>literal text</script>'), findsOneWidget);
    },
  );
}
