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

  testWidgets(
    'declarative view supports checkbox and option_group (single & multi-select)',
    (tester) async {
      String? lastCommand;
      Map<String, Object?>? lastCommandArgs;
      final inputs = <String, String>{};
      final view = <String, dynamic>{
        'type': 'card',
        'children': [
          {
            'type': 'checkbox',
            'id': 'auto_approve',
            'label': 'Enable YOLO Auto-Approve',
            'checked': false,
            'command': 'toggle_yolo',
          },
          {
            'type': 'option_group',
            'id': 'features',
            'label': 'Select checks to run',
            'multiSelect': true,
            'command': 'submit_checks',
            'options': [
              {'id': 'lint', 'label': 'Run Linter', 'value': 'cargo clippy', 'checked': true},
              {'id': 'test', 'label': 'Run Unit Tests', 'value': 'cargo test', 'checked': false},
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
                onCommand: (name, args) {
                  lastCommand = name;
                  lastCommandArgs = args;
                },
                onInput: (key, value) => inputs[key] = value,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Enable YOLO Auto-Approve'), findsOneWidget);
      expect(find.text('Run Linter'), findsOneWidget);
      expect(find.text('Run Unit Tests'), findsOneWidget);

      await tester.tap(find.text('Enable YOLO Auto-Approve'));
      await tester.pump();
      expect(inputs['auto_approve'], 'true');
      expect(lastCommand, 'toggle_yolo');

      await tester.tap(find.text('Run Unit Tests'));
      await tester.pump();
      expect(inputs['features'], 'cargo clippy,cargo test');

      await tester.tap(find.text('Submit Selected (2)'));
      await tester.pump();
      expect(lastCommand, 'submit_checks');
      expect(lastCommandArgs?['values'], <String>['cargo clippy', 'cargo test']);
    },
  );

  testWidgets(
    'option_group multi-select counts down and auto-submits selected options after configured timeout (5s)',
    (tester) async {
      String? lastCommand;
      Map<String, Object?>? lastCommandArgs;
      final view = <String, dynamic>{
        'type': 'card',
        'children': [
          {
            'type': 'option_group',
            'id': 'checks',
            'label': 'Select checks to run',
            'multiSelect': true,
            'command': 'prompt.select_options',
            'options': [
              {
                'id': 'mem',
                'label': 'Verify memory & swap (free -m)',
                'value': 'Verify memory & swap (free -m)',
                'checked': true,
              },
              {
                'id': 'disk',
                'label': 'Check disk capacity (df -h)',
                'value': 'Check disk capacity (df -h)',
                'checked': true,
              },
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
                autoSubmitTimeoutSeconds: 5,
                onCommand: (name, args) {
                  lastCommand = name;
                  lastCommandArgs = args;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Auto-approving in 5s'), findsOneWidget);
      expect(find.text('Submit Selected (2) · 5s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Auto-approving in 3s'), findsOneWidget);
      expect(find.text('Submit Selected (2) · 3s'), findsOneWidget);
      expect(lastCommand, isNull);

      await tester.pump(const Duration(seconds: 3));
      expect(lastCommand, 'prompt.select_options');
      expect(
        lastCommandArgs?['values'],
        <String>[
          'Verify memory & swap (free -m)',
          'Check disk capacity (df -h)',
        ],
      );
    },
  );
}
