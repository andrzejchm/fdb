/// Benchmark runner for `fdb describe` performance measurement.
///
/// Usage:
///   dart run bin/benchmark_describe.dart [--device <id>]
///
/// The app must already be running on the target device with the benchmark
/// screens available (benchmark_screens.dart in the test_app).
///
/// For each scenario this script:
///   1. Navigates to the scenario screen via fdb tap.
///   2. Waits for the UI to settle.
///   3. Calls fdb describe 10 times, discards the first (cold cache).
///   4. Extracts _timing from each response.
///   5. Reports min/median/p95/max wall-clock and per-phase ms.
library;

import 'dart:convert';
import 'dart:io';

import 'package:fdb/vm_service.dart';

typedef _Scenario = ({String name, String route, String listTileKey});
typedef _TimingResult = ({
  double wallMs,
  double walkMs,
  double hitMs,
  double textMs,
  double serialMs,
  int interactiveCount,
  int payloadChars,
});

const _scenarios = <_Scenario>[
  (name: 'baseline', route: '/benchmark/baseline', listTileKey: 'bench_baseline'),
  (name: 'medium', route: '/benchmark/medium', listTileKey: 'bench_medium'),
  (name: 'stress_list', route: '/benchmark/stress_list', listTileKey: 'bench_stress_list'),
  (name: 'stress_grid', route: '/benchmark/stress_grid', listTileKey: 'bench_stress_grid'),
  (name: 'pathological', route: '/benchmark/pathological', listTileKey: 'bench_pathological'),
];

const _runsPerScenario = 10;

Future<void> main(List<String> args) async {
  // Resolve isolate once.
  stdout.writeln('Connecting to VM service...');
  final isolateId = await checkFdbHelper();
  if (isolateId == null) {
    stderr.writeln('ERROR: fdb_helper not detected. Is the app running?');
    exit(1);
  }
  stdout.writeln('Connected. Isolate: $isolateId');
  stdout.writeln('');

  // Navigate to the benchmark menu first (button on home screen).
  await _navigateTo('go_to_benchmarks', isolateId);
  await Future<void>.delayed(const Duration(milliseconds: 800));

  final allResults = <String, List<_TimingResult>>{};

  for (final scenario in _scenarios) {
    stdout.writeln('━━━ ${scenario.name} ━━━');
    // Tap the scenario list tile on the benchmark menu.
    await _navigateTo(scenario.listTileKey, isolateId);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final results = <_TimingResult>[];

    for (var run = 0; run < _runsPerScenario; run++) {
      final wallSw = Stopwatch()..start();
      final response = await vmServiceCall(
        'ext.fdb.describe',
        params: {'isolateId': isolateId},
      );
      wallSw.stop();
      final wallMs = wallSw.elapsedMicroseconds / 1000.0;

      final result = unwrapRawExtensionResult(response);
      if (result is! Map<String, dynamic>) {
        stderr.writeln('  run $run: unexpected response type');
        continue;
      }

      final timing = result['_timing'] as Map<String, dynamic>?;
      final interactive = (result['interactive'] as List<dynamic>?)?.length ?? 0;
      final payloadChars = timing?['payload_chars'] as num? ?? 0;

      final tr = (
        wallMs: wallMs,
        walkMs: (timing?['walk_ms'] as num?)?.toDouble() ?? 0,
        hitMs: (timing?['hit_ms'] as num?)?.toDouble() ?? 0,
        textMs: (timing?['text_ms'] as num?)?.toDouble() ?? 0,
        serialMs: (timing?['serial_ms'] as num?)?.toDouble() ?? 0,
        interactiveCount: interactive,
        payloadChars: payloadChars.toInt(),
      );

      final isCold = run == 0;
      stdout.writeln(
        '  run ${(run + 1).toString().padLeft(2)}'
        '${isCold ? " (cold)" : "       "}'
        '  wall=${wallMs.toStringAsFixed(1).padLeft(7)} ms'
        '  walk=${tr.walkMs.toStringAsFixed(1).padLeft(6)} ms'
        '  hit=${tr.hitMs.toStringAsFixed(1).padLeft(6)} ms'
        '  text=${tr.textMs.toStringAsFixed(1).padLeft(6)} ms'
        '  serial=${tr.serialMs.toStringAsFixed(1).padLeft(5)} ms'
        '  entries=${tr.interactiveCount}'
        '  payload=${tr.payloadChars} chars',
      );

      results.add(tr);
    }

    allResults[scenario.name] = results;

    // Navigate back to benchmark menu for next scenario.
    await _back(isolateId);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  stdout.writeln('');
  stdout.writeln('═══════════════════════════════════════════');
  stdout.writeln('SUMMARY (warm runs only — first run excluded)');
  stdout.writeln('═══════════════════════════════════════════');

  for (final scenario in _scenarios) {
    final runs = allResults[scenario.name] ?? [];
    if (runs.length < 2) {
      stdout.writeln('${scenario.name}: not enough data');
      continue;
    }
    // Discard first (cold) run.
    final warm = runs.sublist(1);
    stdout.writeln('');
    stdout.writeln('Scenario: ${scenario.name}');
    _printStats('  wall (ms)', warm.map((r) => r.wallMs).toList());
    _printStats('  walk (ms)', warm.map((r) => r.walkMs).toList());
    _printStats('  hit  (ms)', warm.map((r) => r.hitMs).toList());
    _printStats('  text (ms)', warm.map((r) => r.textMs).toList());
    _printStats('  serial(ms)', warm.map((r) => r.serialMs).toList());
    stdout.writeln(
      '  entries: ${warm.first.interactiveCount}'
      '  payload: ${warm.first.payloadChars} chars'
      ' (~${(warm.first.payloadChars / 4).round()} tokens)',
    );
  }

  // Print raw JSON for copy-paste into the report.
  stdout.writeln('');
  stdout.writeln('RAW_JSON_START');
  final jsonData = <String, dynamic>{};
  for (final scenario in _scenarios) {
    final runs = allResults[scenario.name] ?? [];
    if (runs.length < 2) continue;
    final warm = runs.sublist(1);
    jsonData[scenario.name] = {
      'wall_ms': _statsMap(warm.map((r) => r.wallMs).toList()),
      'walk_ms': _statsMap(warm.map((r) => r.walkMs).toList()),
      'hit_ms': _statsMap(warm.map((r) => r.hitMs).toList()),
      'text_ms': _statsMap(warm.map((r) => r.textMs).toList()),
      'serial_ms': _statsMap(warm.map((r) => r.serialMs).toList()),
      'entries': runs.first.interactiveCount,
      'payload_chars': runs.first.payloadChars,
      'approx_tokens': (runs.first.payloadChars / 4).round(),
    };
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(jsonData));
  stdout.writeln('RAW_JSON_END');
}

/// Navigate to a list tile by key on the current screen.
Future<void> _navigateTo(String key, String isolateId) async {
  await vmServiceCall(
    'ext.fdb.tap',
    params: {'isolateId': isolateId, 'key': key},
  );
}

Future<void> _back(String isolateId) async {
  await vmServiceCall(
    'ext.fdb.back',
    params: {'isolateId': isolateId},
  );
}

void _printStats(String label, List<double> values) {
  final stats = _statsMap(values);
  stdout.writeln(
    '${label.padRight(12)}'
    '  min=${_fmt(stats['min']!)}'
    '  median=${_fmt(stats['median']!)}'
    '  p95=${_fmt(stats['p95']!)}'
    '  max=${_fmt(stats['max']!)}',
  );
}

String _fmt(double v) => v.toStringAsFixed(1).padLeft(6);

Map<String, double> _statsMap(List<double> values) {
  final sorted = [...values]..sort();
  return {
    'min': sorted.first,
    'median': _percentile(sorted, 50),
    'p95': _percentile(sorted, 95),
    'max': sorted.last,
  };
}

double _percentile(List<double> sorted, int p) {
  if (sorted.isEmpty) return 0;
  final idx = (p / 100 * (sorted.length - 1)).round();
  return sorted[idx.clamp(0, sorted.length - 1)];
}
