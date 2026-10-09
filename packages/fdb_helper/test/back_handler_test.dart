import 'dart:convert';

import 'package:fdb_helper/src/handlers/back_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `fdb back` must do what the Android back button does. These tests assert the
/// outcome a real back press has in each kind of app, including the cases where
/// the app itself does not route back to a nested navigator.
void main() {
  late List<String> systemNavigatorCalls;

  setUp(() => systemNavigatorCalls = []);

  Future<Map<String, dynamic>> back(WidgetTester tester) async {
    final response = (await tester.runAsync(() => handleBack('ext.fdb.back', const {})))!;
    await tester.pumpAndSettle();
    expect(response.errorDetail, isNull);
    return jsonDecode(response.result!) as Map<String, dynamic>;
  }

  Future<void> pumpApp(WidgetTester tester, Widget app) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('SystemNavigator.pop')) systemNavigatorCalls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  NavigatorState rootNavigatorOf(WidgetTester tester, String text) =>
      Navigator.of(tester.element(find.text(text)), rootNavigator: true);

  group('plain MaterialApp', () {
    testWidgets('pops the pushed screen', (tester) async {
      await pumpApp(tester, MaterialApp(home: _screen('Home')));
      rootNavigatorOf(tester, 'Home').push(_route('Pushed'));
      await tester.pumpAndSettle();

      expect(await back(tester), {'status': 'Success', 'popped': true, 'passedToOs': false});
      expect(find.text('Pushed'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(systemNavigatorCalls, isEmpty);
    });

    testWidgets('at the root screen nothing handles back; off Android the app is left alone', (tester) async {
      await pumpApp(tester, MaterialApp(home: _screen('Home')));

      // Tests run on the host (not Android), which has no system back button.
      expect(await back(tester), {'status': 'Success', 'popped': false, 'passedToOs': false});
      expect(systemNavigatorCalls, isEmpty, reason: 'SystemNavigator.pop quits a macOS app');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('leaves no observer behind', (tester) async {
      await pumpApp(tester, MaterialApp(home: _screen('Home')));
      await back(tester);

      // With the temporary observer gone, an unhandled pop reaches SystemNavigator.pop again.
      await tester.binding.handlePopRoute();
      expect(systemNavigatorCalls, ['SystemNavigator.pop']);
    });

    testWidgets('a PopScope that blocks the pop receives the back and the screen stays', (tester) async {
      var blockedPops = 0;
      await pumpApp(tester, MaterialApp(home: _screen('Home')));
      rootNavigatorOf(tester, 'Home').push(
        MaterialPageRoute<void>(
          builder: (_) => PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) => blockedPops++,
            child: _screen('Guarded'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect((await back(tester))['popped'], isTrue);
      expect(blockedPops, 1);
      expect(find.text('Guarded'), findsOneWidget);
    });

    testWidgets('dismisses a dialog before the screen below it', (tester) async {
      await pumpApp(tester, MaterialApp(home: _screen('Home')));
      showDialog<void>(
        context: tester.element(find.text('Home')),
        builder: (_) => const AlertDialog(title: Text('Confirm')),
      );
      await tester.pumpAndSettle();

      expect((await back(tester))['popped'], isTrue);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('nested Navigator in a plain MaterialApp', () {
    late GlobalKey<NavigatorState> nestedKey;

    Future<void> pumpNested(WidgetTester tester, {required bool popHandler}) async {
      nestedKey = GlobalKey<NavigatorState>();
      await pumpApp(tester, MaterialApp(home: _screen('Home')));
      rootNavigatorOf(tester, 'Home').push(
        _route('Host', body: _NestedHost(navigatorKey: nestedKey, popHandler: popHandler)),
      );
      await tester.pumpAndSettle();
      nestedKey.currentState!.pushNamed('Details');
      await tester.pumpAndSettle();
    }

    testWidgets('with NavigatorPopHandler: pops the nested screen first, then the host', (tester) async {
      await pumpNested(tester, popHandler: true);

      expect((await back(tester))['popped'], isTrue);
      expect(find.text('Details'), findsNothing);
      expect(find.text('List'), findsOneWidget);

      expect((await back(tester))['popped'], isTrue);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('without back wiring: pops the host route, as a real back press does in such an app', (tester) async {
      await pumpNested(tester, popHandler: false);

      expect((await back(tester))['popped'], isTrue);
      expect(find.text('Details'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('MaterialApp.router with a nested navigator (auto_route style)', () {
    late GlobalKey<NavigatorState> nestedKey;
    late _TestRouterDelegate delegate;

    Future<void> pumpRouterApp(WidgetTester tester) async {
      nestedKey = GlobalKey<NavigatorState>();
      delegate = _TestRouterDelegate(nestedKey);
      await pumpApp(
        tester,
        MaterialApp.router(routerDelegate: delegate, routeInformationParser: _TestRouteParser()),
      );
      nestedKey.currentState!.pushNamed('Details');
      await tester.pumpAndSettle();
    }

    testWidgets('the router decides: nested screen, then router page, then nothing', (tester) async {
      await pumpRouterApp(tester);

      expect((await back(tester))['popped'], isTrue);
      expect(find.text('Details'), findsNothing);
      expect(find.text('List'), findsOneWidget);
      expect(delegate.pages, ['Home', 'Host']);

      expect((await back(tester))['popped'], isTrue);
      expect(delegate.pages, ['Home']);
      expect(find.text('Home'), findsOneWidget);
      expect(systemNavigatorCalls, isEmpty);

      expect(await back(tester), {'status': 'Success', 'popped': false, 'passedToOs': false});
      expect(systemNavigatorCalls, isEmpty);
    });
  });
}

Widget _screen(String title, {Widget? body}) => Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: body ?? Center(child: Text('body of $title')),
    );

Route<void> _route(String title, {Widget? body}) =>
    MaterialPageRoute<void>(settings: RouteSettings(name: title), builder: (_) => _screen(title, body: body));

/// A screen hosting its own [Navigator], starting on a `List` screen. With
/// [popHandler] it forwards back presses to that navigator the way Flutter
/// recommends ([NavigatorPopHandler]).
class _NestedHost extends StatelessWidget {
  const _NestedHost({required this.navigatorKey, this.popHandler = true});

  final GlobalKey<NavigatorState> navigatorKey;
  final bool popHandler;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => switch (settings.name) {
        'Details' => _route('Details'),
        _ => _route('List'),
      },
    );
    if (!popHandler) return navigator;
    return NavigatorPopHandler<void>(
      onPopWithResult: (_) => navigatorKey.currentState!.maybePop(),
      child: navigator,
    );
  }
}

/// Root [Router] delegate with a page-based [Navigator]; the `Host` page embeds
/// a nested [Navigator]. Like auto_route, [popRoute] pops the innermost
/// navigator that can pop before its own pages.
class _TestRouterDelegate extends RouterDelegate<String> with ChangeNotifier {
  _TestRouterDelegate(this.nestedKey);

  final GlobalKey<NavigatorState> nestedKey;
  final _rootKey = GlobalKey<NavigatorState>();

  List<String> pages = ['Home', 'Host'];

  @override
  Widget build(BuildContext context) => Navigator(
        key: _rootKey,
        pages: [
          for (final name in pages)
            MaterialPage<void>(
              key: ValueKey(name),
              name: name,
              child: name == 'Host'
                  ? _screen('Host', body: _NestedHost(navigatorKey: nestedKey, popHandler: false))
                  : _screen(name),
            ),
        ],
        onDidRemovePage: (page) {
          pages = [...pages]..remove(page.name);
          notifyListeners();
        },
      );

  @override
  Future<bool> popRoute() async {
    final nested = nestedKey.currentState;
    if (nested != null && nested.canPop()) return nested.maybePop();
    return await _rootKey.currentState?.maybePop() ?? false;
  }

  @override
  Future<void> setNewRoutePath(String configuration) async {}
}

class _TestRouteParser extends RouteInformationParser<String> {
  @override
  Future<String> parseRouteInformation(RouteInformation routeInformation) async => routeInformation.uri.path;
}
