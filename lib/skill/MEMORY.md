## fdb skill: memory

Memory profiling — heap inspection, forced GC, and heap snapshots.

No `fdb_helper` required for any of these commands — they use the VM service directly and work on any platform fdb supports.

## Contents
- Best practices
- Heap memory inspection
- Forced garbage collection
- Heap snapshot (DevTools-loadable)
- Leak-hunting workflow

## Best practices

- **Always `fdb gc` before profiling.** Dart's GC is not deterministic. A heap snapshot or profile taken without a preceding GC will contain objects that are already unreachable but not yet collected — this creates false positives in leak analysis. Run `fdb gc` immediately before every `fdb mem profile` or `fdb heap dump`.
- **Never interpret a single profile.** A raw heap snapshot tells you what's allocated, not whether it's leaking. Always diff two profiles — one before and one after the suspected-leak scenario.
- **Use `fdb mem diff` before `fdb heap dump`.** The diff is fast and text-based. Only reach for a full heap snapshot when the diff points to a class whose retaining path you need to explore in DevTools.
- **Navigate the suspect scenario at least 3 times before the second profile.** A single navigation may leave transient objects. Repeated navigation makes true leaks stand out clearly in the diff.
- **Sort by bytes (`--sort bytes`) when objects are large.** The default sort is by instance count, which highlights many small objects. For large retained objects (e.g. image caches, large BLoC state), sort by bytes instead.

## Heap memory inspection

```bash
fdb mem                              # per-isolate heap totals (human-readable table)
fdb mem --json                       # same, machine-readable JSON

fdb mem profile --output before.json            # capture allocation profile to file
fdb mem profile --output before.json --isolate isolates/123   # specific isolate
fdb mem profile --output before.json --all-isolates           # one file per isolate
```

`fdb mem` output:
```
isolate                          heapUsage    external    capacity
------------------------------------------------------------------
main                               81.0 MB      5.5 KB     89.5 MB
------------------------------------------------------------------
TOTAL                              81.0 MB      5.5 KB     89.5 MB
```

`fdb mem profile` output (one line per key):
```
MEM_PROFILE_SAVED=/tmp/before.json
CLASSES=6405
ISOLATE=main
```

**Diff two profiles:**
```bash
fdb mem diff before.json after.json           # top 20 classes by instance count delta
fdb mem diff before.json after.json --all     # all changed classes
fdb mem diff before.json after.json --sort bytes  # sort by byte delta instead
fdb mem diff before.json after.json --json    # machine-readable JSON
```

`fdb mem diff` output:
```
Top 3 changed classes (by instance count delta):
   +12  ProductPageBloc                           12 -> 24
   +12  StreamSubscriptionImpl<Product>           47 -> 59
    +8  _ProductImageState                         4 -> 12
```

## Forced garbage collection

```bash
fdb gc           # force GC across all isolates; human-readable summary
fdb gc --json    # same, KEY=value tokens for scripting
```

`fdb gc` output:
```
GC_COMPLETE HEAP_BEFORE=322.4 MB HEAP_AFTER=287.1 MB HEAP_DELTA=-35.3 MB
```

`fdb gc --json` output:
```
HEAP_BEFORE=338033664
HEAP_AFTER=301020160
HEAP_DELTA=-37013504
```

## Heap snapshot (DevTools-loadable)

```bash
fdb heap dump --output leak.heapsnapshot          # capture snapshot (GC first)
fdb heap dump --output leak.heapsnapshot --no-gc  # skip pre-snapshot GC
fdb heap dump --output leak.heapsnapshot --isolate isolates/123  # specific isolate
```

`fdb heap dump` output:
```
SNAPSHOT_SAVED=leak.heapsnapshot
Wrote 47.2 MB. Open in DevTools: Memory tab -> Import snapshot
```

Open the snapshot in Chrome DevTools: `Memory` tab → `Load` (or `Import snapshot`) → select the `.heapsnapshot` file. Use the `Summary` view for retained-size trees, or the `Comparison` view to diff two snapshots.

## Leak-hunting workflow

```bash
# 1. Force GC to clear unreachable objects
fdb gc

# 2. Capture baseline
fdb mem profile --output /tmp/before.json

# 3. Navigate through the suspected-leak scenario (repeat 3+ times for clarity)
#    e.g. open ProductPage → go back, repeatedly

# 4. Force GC again to remove transient objects
fdb gc

# 5. Capture post-scenario profile
fdb mem profile --output /tmp/after.json

# 6. Diff — focus on classes with growing instance counts
fdb mem diff /tmp/before.json /tmp/after.json

# If a class is suspicious and you need the retaining path:
fdb heap dump --output /tmp/leak.heapsnapshot
# Then open in Chrome DevTools Memory tab
```

Classes whose counts keep growing proportionally to the number of navigations are strong leak indicators. `StreamSubscription`, `BLoC`, and `State` objects that don't decrease after navigating back are common culprits.
