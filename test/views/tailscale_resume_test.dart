import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/tailscale.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

/// A login finishes in a browser, so the page is off screen when the node is
/// signed in. What that costs is worth a test of its own: the read that reports
/// it has to happen when the app comes back, not on a timer the browser took
/// off screen with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockCoreHandlerInterface core;
  late ProviderContainer container;

  final signedIn = TailscaleStatus.fromJson({
    'name': kTailscaleProxyName,
    'backend-state': 'Running',
    'auth-method': 'browser',
    'have-node-key': true,
    'online': true,
    'ips': ['100.84.146.60'],
    'peers': [
      {
        'hostname': 'Revision-PC',
        'os': 'windows',
        'ips': ['100.106.43.107'],
        'online': false,
      },
    ],
  });

  setUp(() {
    core = _MockCoreHandlerInterface();
    when(
      () => core.tailscaleStatus(kTailscaleProxyName),
    ).thenAnswer((_) async => signedIn);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(900, 1600);
  });

  tearDown(() => container.dispose());

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    container
        .read(tailscaleSettingProvider.notifier)
        .update((state) => state.copyWith(inject: true));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: TailscaleView()),
      ),
    );
    await tester.pump();
  }

  testWidgets('a node signed in while the browser was open is read on return', (
    tester,
  ) async {
    await pumpView(tester);
    // The browser took the app away, and control signed the node in meanwhile.
    // Polling is not a route back to that: the timer goes with the page, so the
    // read on return is the only thing that reports it.
    clearInteractions(core);

    // The states are walked in the order a phone reports them, because the
    // framework rejects a jump from one to another.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    verifyNever(() => core.tailscaleStatus(kTailscaleProxyName));

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();

    verify(() => core.tailscaleStatus(kTailscaleProxyName)).called(1);
    expect(find.text('Signed in with a browser'), findsOneWidget);
    expect(find.textContaining('100.84.146.60'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  // A button that promises a page has to say what happened when control hands
  // out none. Saying "already signed in" about a node that never got that far
  // is a lie the fresh install showed, so the two answers stay apart.
  testWidgets('an empty login URL on a node that is not running is not a '
      'sign-in', (tester) async {
    when(() => core.tailscaleStatus(kTailscaleProxyName)).thenAnswer(
      (_) async => TailscaleStatus.fromJson({
        'name': kTailscaleProxyName,
        'backend-state': 'NeedsLogin',
      }),
    );
    when(
      () => core.tailscaleLoginUrl(kTailscaleProxyName),
    ).thenAnswer((_) async => '');

    await pumpView(tester);

    await tester.tap(find.text('Browser sign-in'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The node has not reported a sign-in page yet, so try again in a moment',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'This device is already signed in, so there is nothing to finish',
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });

  // With no core there is nothing that would answer for the node, and a page
  // that said "Starting" would keep saying it for as long as the user waited.
  testWidgets('a node with no core behind it has not started', (tester) async {
    when(
      () => core.tailscaleStatus(kTailscaleProxyName),
    ).thenAnswer((_) async => null);

    await pumpView(tester);

    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Starting'), findsNothing);

    // The page polls while the node is unsettled and riverpod schedules its
    // own disposal, so both have to be given the frame that ends them.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
