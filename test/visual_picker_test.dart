import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/models.dart';
import 'package:aurasync/ui/screens/visual_preview_screen.dart';
import 'package:aurasync/ui/visual_catalog.dart';
import 'package:aurasync/ui/widgets/sensory_shader_view.dart';
import 'package:aurasync/ui/widgets/visual_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('visual catalog', () {
    test('every visual mode is offered exactly once', () {
      final modes = kVisualOptions.map((o) => o.mode).toList();
      expect(modes.toSet(), VisualMode.values.toSet());
      expect(modes, hasLength(VisualMode.values.length));
    });

    test('each animation has a distinct name and a description', () {
      expect(kVisualOptions.map((o) => o.title).toSet(),
          hasLength(kVisualOptions.length));
      for (final o in kVisualOptions) {
        expect(o.title.length, lessThanOrEqualTo(20), reason: o.title);
        expect(o.description, isNotEmpty);
      }
    });

    test('every animated option maps to its own shader file that exists', () {
      final seen = <ShaderKind>{};
      for (final o in kVisualOptions) {
        final kind = o.shader;
        if (o.mode == VisualMode.auto || o.mode == VisualMode.blackScreen) {
          expect(kind, isNull, reason: '${o.mode} has no fixed shader');
          continue;
        }
        expect(kind, isNotNull, reason: '${o.mode}');
        expect(seen.add(kind!), isTrue, reason: 'two options share $kind');
        expect(File(SensoryShaderView.assetFor(kind)).existsSync(), isTrue,
            reason: SensoryShaderView.assetFor(kind));
      }
      expect(seen, ShaderKind.values.toSet(),
          reason: 'every shader is reachable by a caregiver');
    });

    test('the choice is stored by name and survives every mode', () {
      for (final mode in VisualMode.values) {
        final p = const SensoryProfile().copyWith(visualMode: mode);
        expect(SensoryProfile.fromMap(p.toMap()).visualMode, mode);
      }
    });
  });

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('VisualPicker', () {
    testWidgets('shows every animation and marks the current one',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          host(VisualPicker(value: VisualMode.aurora, onChanged: (_) {})));
      expect(tester.takeException(), isNull);
      for (final o in kVisualOptions) {
        expect(find.text(o.title), findsOneWidget, reason: o.title);
      }
      final selected =
          tester.getSemantics(find.bySemanticsLabel(RegExp('^Aurora\\.')));
      expect(selected.flagsCollection.isSelected, ui.Tristate.isTrue);
    });

    testWidgets('tapping a card selects it', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VisualMode? picked;
      await tester.pumpWidget(host(
          VisualPicker(value: VisualMode.auto, onChanged: (m) => picked = m)));
      await tester.tap(find.text('Crystal polygons'));
      expect(picked, VisualMode.crystals);
      await tester.tap(find.text('Black screen'));
      expect(picked, VisualMode.blackScreen);
    });

    testWidgets('automatic has no preview, the others do', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          host(VisualPicker(value: VisualMode.auto, onChanged: (_) {})));
      expect(find.byTooltip('Preview Automatic'), findsNothing);
      expect(find.byTooltip('Preview Polygon mandala'), findsOneWidget);
      expect(find.byTooltip('Preview Black screen'), findsOneWidget);
    });

    testWidgets('lays out on a small phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          host(VisualPicker(value: VisualMode.auto, onChanged: (_) {})));
      expect(tester.takeException(), isNull);
    });

    testWidgets('preview opens full screen and closes again', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          host(VisualPicker(value: VisualMode.auto, onChanged: (_) {})));
      await tester.tap(find.byTooltip('Preview Starfield'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(VisualPreviewScreen), findsOneWidget);
      expect(find.text('Starfield · preview'), findsOneWidget);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      expect(find.byType(VisualPreviewScreen), findsNothing);
    });
  });
}
