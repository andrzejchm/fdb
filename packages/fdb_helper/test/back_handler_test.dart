import 'dart:convert';

import 'package:fdb_helper/src/handlers/back_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _back(WidgetTester tester) async {
  final response = (await tester.runAsync(() => handleBack('ext.fdb.back', const {})))!;
  await tester.pumpAndSettle();
  return jsonDecode(response.result!) as Map<String, dynamic>;
}

Widget _screen(String title, {Widget? body}) => Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: body ?? Center(child: Text('body of $title')),
    );

Route<void> _route(String title, {Widget? body}) =>
    MaterialPageRoute<void>(settings: RouteSettings(name: title), builder: (_) => _screen(title, body: body));

/// A screen that hosts its own nested [Navigator] (like an auto_route `AutoRouter`
/// or a tab shell), starting on a `List` screen.
class _NestedHost extends StatelessWidget {
  const _NestedHost({required this.navigatorKey, this.popScopeOnDetails = false});

  final GlobalKey<NavigatorState> navigatorKey;
  final bool popScopeOnDetails;

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        onGenerateRoute: (settings) => switch (settings.name) {
          'Details' => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => PopScope(canPop: !popScopeOnDetails, child: _screen('Details')),
            ),
          _ => _route('List'),
        },
      );
}

void main() {
  group('plain single Navigator', () {
    testWidgets('pops the pushed screen and reports popped: true', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _screen('Home')));
      Navigator.of(tester.element(find.text('Home'))).push(_route('Pushed'));
      await tester.pumpAndSettle();

      final result = await _back(tester);

      expect(result, {'status': 'Success', 'popped': true});
      expect(find.text('Pushed'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('at the root reports popped: false and leaves the app alone', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _screen('Home')));

      final result = await _back(tester);

      expect(result, {'status': 'Success', 'popped': false});
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a PopScope that blocks the pop is reported as handled without popping', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _screen('Home')));
      Navigator.of(tester.element(find.text('Home'))).push(
        MaterialPageRoute<void>(builder: (_) => PopScope(canPop: false, child: _screen('Guarded'))),
      );
      await tester.pumpAndSettle();

      final result = await _back(tester);

      expect(result['popped'], isTrue);
      expect(find.text('Guarded'), findsOneWidget);
    });

    testWidgets('reports an error when the app has no Navigator', (tester) async {
      await tester.pumpWidget(const SizedBox());

      final response = (await tester.runAsync(() => handleBack('ext.fdb.back', const {})))!;

      expect(response.errorDetail, contains('No Navigator found'));
    });
  });

  group('nested Navigator inside the root Navigator', () {
    late GlobalKey<NavigatorState> nestedKey;

    Future<void> pumpNested(WidgetTester tester, {bool popScopeOnDetails = false}) async {
      nestedKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(home: _screen('Home')));
      Navigator.of(tester.element(find.text('Home'))).push(
        _route('Host', body: _NestedHost(navigatorKey: nestedKey, popScopeOnDetails: popScopeOnDetails)),
      );
      await tester.pumpAndSettle();
      nestedKey.currentState!.pushNamed('Details');
      await tester.pumpAndSettle();
    }

    testWidgets('pops the nested screen, not the root route hosting it', (tester) async {
      await pumpNested(tester);

      final result = await _back(tester);

      expect(result, {'status': 'Success', 'popped': true});
      expect(find.text('Details'), findsNothing);
      expect(find.text('List'), findsOneWidget);
    });

    testWidgets('once the nested navigator is at its root, back pops the root route that hosts it', (tester) async {
      await pumpNested(tester);
      await _back(tester);

      final result = await _back(tester);

      expect(result, {'status': 'Success', 'popped': true});
      expect(find.text('List'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a dialog on the root navigator is dismissed before the nested screen', (tester) async {
      await pumpNested(tester);
      showDialog<void>(
        context: tester.element(find.text('Details')),
        builder: (_) => const AlertDialog(title: Text('Confirm')),
      );
      await tester.pumpAndSettle();

      final result = await _back(tester);

      expect(result['popped'], isTrue);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('a PopScope on the nested screen intercepts the back', (tester) async {
      await pumpNested(tester, popScopeOnDetails: true);

      final result = await _back(tester);

      expect(result['popped'], isTrue);
      expect(find.text('Details'), findsOneWidget);
    });
  });

  group('hidden nested navigators are left alone', () {
    // Tab 0 is visible; the hidden tab 1 is built later in the tree and also has a screen to pop.
    final hiddenTabVariants = <String, Widget Function(List<GlobalKey<NavigatorState>> keys)>{
      'IndexedStack': (keys) => IndexedStack(
            index: 0,
            children: [for (final key in keys) _NestedHost(navigatorKey: key)],
          ),
      'Offstage': (keys) => Column(
            children: [
              Expanded(child: _NestedHost(navigatorKey: keys[0])),
              Offstage(child: SizedBox(height: 100, child: _NestedHost(navigatorKey: keys[1]))),
            ],
          ),
      'Visibility(maintainSize)': (keys) => Column(
            children: [
              Expanded(child: _NestedHost(navigatorKey: keys[0])),
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: SizedBox(height: 100, child: _NestedHost(navigatorKey: keys[1])),
              ),
            ],
          ),
    };

    for (final MapEntry(key: name, value: buildTabs) in hiddenTabVariants.entries) {
      testWidgets('$name: only the visible tab is popped', (tester) async {
        final tabKeys = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];
        await tester.pumpWidget(MaterialApp(home: buildTabs(tabKeys)));
        tabKeys[0].currentState!.pushNamed('Details');
        tabKeys[1].currentState!.pushNamed('Details');
        await tester.pumpAndSettle();

        final result = await _back(tester);

        expect(result['popped'], isTrue);
        expect(tabKeys[0].currentState!.canPop(), isFalse, reason: 'the visible tab was popped');
        expect(tabKeys[1].currentState!.canPop(), isTrue, reason: 'the hidden tab must be left alone');
      });
    }
  });

  group('Router based app (MaterialApp.router)', () {
    late GlobalKey<NavigatorState> nestedKey;
    late _TestRouterDelegate delegate;

    Future<void> pumpRouterApp(WidgetTester tester) async {
      nestedKey = GlobalKey<NavigatorState>();
      delegate = _TestRouterDelegate(nestedKey);
      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: _TestRouteParser(),
        ),
      );
      await tester.pumpAndSettle();
      nestedKey.currentState!.pushNamed('Details');
      await tester.pumpAndSettle();
    }

    testWidgets('pops the nested screen and keeps the router page stack in sync', (tester) async {
      await pumpRouterApp(tester);
      expect(delegate.pages, ['Home', 'Host']);

      final result = await _back(tester);

      expect(result, {'status': 'Success', 'popped': true});
      expect(find.text('Details'), findsNothing);
      expect(find.text('List'), findsOneWidget);
      expect(delegate.pages, ['Home', 'Host'], reason: 'the nested pop must not remove the hosting router page');
    });

    testWidgets('then pops the router page, and stops at the router root', (tester) async {
      await pumpRouterApp(tester);
      await _back(tester);

      expect((await _back(tester))['popped'], isTrue);
      expect(delegate.pages, ['Home']);
      expect(find.text('Home'), findsOneWidget);

      expect(await _back(tester), {'status': 'Success', 'popped': false});
    });
  });
}

/// Root [Router] delegate with a page-based [Navigator]; the `Host` page embeds a
/// nested plain [Navigator], like a nested auto_route / go_router shell.
class _TestRouterDelegate extends RouterDelegate<String> with ChangeNotifier, PopNavigatorRouterDelegateMixin<String> {
  _TestRouterDelegate(this.nestedKey);

  final GlobalKey<NavigatorState> nestedKey;

  @override
  final navigatorKey = GlobalKey<NavigatorState>();

  List<String> pages = ['Home', 'Host'];

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        pages: [
          for (final name in pages)
            MaterialPage<void>(
              key: ValueKey(name),
              name: name,
              child: name == 'Host' ? _screen('Host', body: _NestedHost(navigatorKey: nestedKey)) : _screen(name),
            ),
        ],
        onDidRemovePage: (page) {
          pages = [...pages]..remove(page.name);
          notifyListeners();
        },
      );

  @override
  Future<void> setNewRoutePath(String configuration) async {}
}

class _TestRouteParser extends RouteInformationParser<String> {
  @override
  Future<String> parseRouteInformation(RouteInformation routeInformation) async => routeInformation.uri.path;
}
