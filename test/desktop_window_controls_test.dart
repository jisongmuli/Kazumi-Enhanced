import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/appbar/desktop_window_controls.dart';
import 'package:kazumi/pages/portal/portal_header.dart';

void main() {
  const channel = MethodChannel('window_manager');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var fullscreen = false;

  setUp(() {
    calls.clear();
    fullscreen = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'isFullScreen') return fullscreen;
      if (call.method == 'setFullScreen') {
        fullscreen = (call.arguments as Map)['isFullScreen'] as bool;
      }
      return null;
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'three controls call native minimize, fullscreen/restore and the existing close signal',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DesktopWindowControls())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('最小化'));
      await tester.pumpAndSettle();
      expect(calls.any((call) => call.method == 'minimize'), isTrue);
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(fullscreen, isTrue);
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.tap(find.byTooltip('退出全屏'));
      await tester.pumpAndSettle();
      expect(fullscreen, isFalse);
      expect(
        calls
            .where((call) => call.method == 'setFullScreen')
            .map((call) => (call.arguments as Map)['isFullScreen']),
        [true, false],
      );
      await tester.tap(find.byTooltip('关闭窗口'));
      await tester.pumpAndSettle();
      expect(calls.any((call) => call.method == 'close'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native fullscreen changes update the button even when another page changed the window state',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DesktopWindowControls())),
      );
      await tester.pumpAndSettle();
      fullscreen = true;
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {'eventName': 'enter-full-screen'}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      fullscreen = false;
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {'eventName': 'leave-full-screen'}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('全屏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1280.0, 1050.0, 840.0]) {
    testWidgets(
      'portal controls remain on the top right at width $width without overlapping navigation/search',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PortalHeader(
                selectedIndex: 5,
                onNavigate: (_) {},
                onSearch: (_) {},
                onHistory: () {},
                onMore: (_) {},
                windowControls: const DesktopWindowControls(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final close = tester.getRect(find.byTooltip('关闭窗口'));
        final minimize = tester.getRect(find.byTooltip('最小化'));
        final search = tester.getRect(
          find.byKey(const ValueKey('portal-global-search')),
        );
        expect(close.right, greaterThan(width - 30));
        expect(close.top, lessThan(30));
        expect(search.right, lessThan(minimize.left));
        expect(find.byTooltip('全屏'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
