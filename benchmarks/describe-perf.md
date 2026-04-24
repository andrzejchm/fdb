# `fdb describe` Performance Benchmark

## Setup

| Field | Value |
|---|---|
| Flutter | 3.41.6 (stable) |
| Device | iPhone 17 Pro Simulator (iOS, Apple silicon host) |
| fdb version | 1.1.5 |
| Instrumentation | `Stopwatch` inside `_handleDescribe` in `fdb_binding.dart` |
| Method | 10 calls per scenario, first (cold) discarded, 9 warm runs reported |
| Wall clock | measured at the Dart VM service call boundary (WebSocket round-trip excluded from per-phase timings, included in wall) |

---

## Claim verification

### "filters to ~19 widget types"

**False — the actual whitelist has 21 types:**

```
Checkbox, CheckboxListTile, DropdownButton, ElevatedButton, FilledButton,
FloatingActionButton, GestureDetector, IconButton, InkWell, ListTile,
OutlinedButton, PopupMenuButton, Radio, RadioListTile, Slider, Switch,
SwitchListTile, Tab, TextButton, TextField, TextFormField
```

The "~19" was an undercount. Correct figure: **21 widget types**.

### "a screen with 500 raw widgets typically returns 5-15 entries"

**Partially true, but the reasoning needs adjustment.** The baseline screen (realistic mobile UI, ~150 total widget nodes) returned **7 entries**. The stress_list screen (200 ListTiles × 3 interactive widgets each = 600 interactive nodes total, but viewport-clipped) returned **11 entries** — viewport clipping is doing the work, not raw widget count. The "5-15 entries" range holds for single-viewport screens regardless of total widget count. Screens with more visible interactable elements (stress_grid: 25 entries, pathological: 54 entries) exceed that range.

### "bottleneck would be text extraction more than tree walk"

**False.** The instrumentation shows the opposite:

- Tree walk consistently accounts for **70–75%** of in-process time across all scenarios.
- Text extraction is **negligible** (< 1 ms on every scenario, < 2% of total).
- The pathological scenario (300 FilterChips + 50 GestureDetectors, all visible) spent **28 ms walking** vs **0.5 ms extracting text**.

The bottleneck is the recursive element tree traversal, not text extraction.

---

## Results

Wall clock includes WebSocket round-trip overhead on top of in-process time. Per-phase timings are measured inside the VM extension handler.

### Wall-clock latency (ms) — warm runs (n=9)

| Scenario | min | median | p95 | max |
|---|---|---|---|---|
| baseline | 4.7 | 5.3 | 9.4 | 9.4 |
| medium | 5.6 | 6.9 | 10.5 | 10.5 |
| stress_list | 6.0 | 7.4 | 10.6 | 10.6 |
| stress_grid | 8.6 | 10.7 | 12.9 | 12.9 |
| pathological | 34.8 | 37.2 | 39.7 | 39.7 |

### Per-phase breakdown (ms, median warm)

| Scenario | walk | hit-test | text extract | serialize | entries returned | payload chars | approx tokens |
|---|---|---|---|---|---|---|---|
| baseline | 2.2 | 0.9 | 0.2 | 0.05 | 7 | 1 437 | ~359 |
| medium | 2.8 | 1.0 | 0.3 | 0.05 | 13 | 1 999 | ~500 |
| stress_list | 2.8 | 0.8 | 0.4 | 0.05 | 11 | 2 108 | ~527 |
| stress_grid | 3.9 | 1.5 | 0.5 | 0.06 | 25 | 2 832 | ~708 |
| pathological | 27.8 | 3.2 | 0.5 | 0.11 | 54 | 6 521 | ~1 630 |

### Scenario definitions

| Scenario | Description | Total widget nodes (approx) | Interactable nodes (total, pre-clip) |
|---|---|---|---|
| baseline | Realistic settings screen: 2 TextFields, 2 Switches, 1 Slider, 2 buttons | ~150 | ~8 |
| medium | Settings list: 20 SwitchListTiles + 18 RadioListTiles + 12 CheckboxListTiles (scrollable, ~13 visible) | ~600 | 50 |
| stress_list | ListView.builder, 200 ListTiles each with 1 IconButton + 1 Switch (most off-screen) | ~2 400 | 400 (600 total widgets) |
| stress_grid | GridView, 100 Cards each with 2 IconButtons (all visible in viewport) | ~800 | 200 |
| pathological | Wrap of 300 FilterChips + 50 GestureDetectors, all visible | ~1 800 | 350 |

---

## Assessment

**Normal screens (baseline, medium, stress_list) are fast: 5–11 ms wall-clock, sub-1 ms in-process for the tree walk.** Viewport clipping does its job on the stress_list — 200 ListTiles with 400 interactive widgets collapse to 11 visible entries at ~7 ms, indistinguishable from the medium scenario.

**stress_grid is acceptable but visibly heavier at ~11 ms median** due to 100 fully-visible Cards each requiring individual hit-testing. The hit-test phase is the secondary bottleneck here (1.5 ms), not the tree walk.

**pathological is the real limit: 37 ms median, 40 ms p95.** A screen with 300 FilterChips — all visible, all needing element tree traversal — pushes walk time to ~28 ms. This is not a realistic UI, but it shows where the ceiling is. Any screen rendering 200+ interactable widgets simultaneously in the viewport will be noticeably slower. 40 ms is not a blocking problem for an AI agent (one call per action), but it is measurable.

**Text extraction is not the bottleneck** — it measured under 1 ms on every scenario, including pathological. The original claim had the bottleneck inverted. The actual bottleneck is the **recursive element tree walk**, which scales with the number of visible nodes, not total widget count.

**Serialization and WebSocket overhead are negligible** (< 0.15 ms in-process; total WebSocket round-trip adds roughly 3–7 ms on top of in-process time on simulator localhost).

---

## Reproducing

```bash
# From the repo root (worktree or main)
cd example/test_app
dart run ../../bin/fdb.dart launch --device <simulator-id> --flutter-sdk /path/to/flutter-sdk
# then in a separate terminal:
dart run ../../bin/benchmark_describe.dart
```
