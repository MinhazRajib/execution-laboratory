# ExecLab

**How much of your alpha survives execution?**

**[Try it in your browser](https://execution-laboratory.vercel.app/)** · [Video walkthrough](https://drive.google.com/file/d/1dd6auNKp75jg_5R7BLBO7D8EiGYoV8io/view)

[![CI](https://github.com/MinhazRajib/execution-laboratory/actions/workflows/ci.yml/badge.svg)](https://github.com/MinhazRajib/execution-laboratory/actions/workflows/ci.yml)
![OCaml 5.2](https://img.shields.io/badge/OCaml-5.2-ec6813)
![Jane Street stack](https://img.shields.io/badge/stack-Core%20%C2%B7%20ppx__jane%20%C2%B7%20Bonsai-3d3d3d)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

A deterministic execution laboratory, written in OCaml in the Jane Street
style. You bring the trade instructions an alpha model produced. ExecLab
runs them through TWAP, VWAP, POV, implementation shortfall, or an
adaptive passive/aggressive algorithm, in a market calibrated to a real
historical session, and tells you exactly where the P&L went:

```
gross alpha  =  net P&L  +  timing  +  spread  +  impact  +  opportunity cost
```

That identity holds to the cent on every run, and an expect test proves it.

The same engine runs three ways: a CLI that prints a cost report, a
league-table sweep that checks invariants over every session in the
catalog, and a Bonsai web client that runs the whole simulation in the
browser and replays it minute by minute. All three share one pure
pipeline, so the same config yields bit-identical fills everywhere.

---

## Sixty seconds

```sh
opam install . --deps-only --with-test
dune build lib bin && dune runtest lib
dune exec bin/main.exe -- examples/demo_alpha_basket.csv 2026-07-09 adaptive
```

That last command trades a five-order basket across TSLA, AAPL, MSFT and
GOOG on one real day, grades every order against its own symbol's arrival
price, close and VWAP, and prints the decomposition next to an
immediate-execution baseline. This is the report block, exactly as the
analytics expect tests pin it (a 100-share buy on a flat $10 test day):

```
=== TWAP ===
NVDA BUY 100 shares
  filled          100 of 100 (100.0%)
  arrival         $10.00
  terminal        $11.00
  day vwap        $10.1500
  avg fill        $10.1000
  shortfall       +100.0 bps ($10.00)
  vs day vwap     -49.3 bps
  timing cost     $0.00
  spread cost     $1.00
  impact cost     $9.00
  gross alpha     $100.00
  net P&L         $90.00
  opportunity     $0.00
  alpha captured  90.0%
=== immediate ===
  ...
```

Swap `adaptive` for `twap`, `vwap`, `pov`, `is` or `immediate`, and append
`synthetic:42` to trade the same alpha in the synthetic exchange with seed
42 instead of the bar model.

---

## What makes it interesting

**Five algorithms, one interface, no look-ahead.** Every algorithm sees
only the *previous* bar when it decides, and returns submit, cancel or
replace actions for child orders. TWAP spreads evenly. VWAP shapes the
schedule to a *leave-one-out* forecast of the symbol's volume curve, so it
can genuinely be wrong on an unusual day. POV chases realized volume and
promises market share, not a finish time. Implementation shortfall follows
the Almgren-Chriss trajectory, with the whole curvature exposed as one
dimensionless `urgency` knob. Adaptive is the only one that decides *how*
to trade rather than how much: it keeps TWAP's trajectory but rests at the
near touch when it is on schedule and crosses when it is behind or when
the tape is in front of the decision price.

**Two fill engines behind one seam.** Engine A is a stateless bar
calculator: aggressive fills pay a half-spread plus square-root impact,
capped by a per-bar participation budget. Engine B is a real limit order
book. Three market-maker archetypes ladder both sides around the
historical price path with depth scaled to bar volume and spreads scaled
to bar range, noise traders print a tape, and client orders walk the
ladders through real price levels. Queue position, depth exhaustion, and
permanent impact (makers remember being run over and requote against you,
decaying over bars) emerge mechanically instead of by formula. Algorithms
cannot tell which world they are in.

**Determinism is the whole product.** Engine B draws every random number
from a pure 32-bit LCG, so the same seed produces bit-identical fills
natively and in the browser. A saved run is just its config, and reopening
it reproduces every fill. That is what makes "rerun this alpha with a
different algorithm" a fair comparison rather than a new experiment.

**Multi-symbol runs are one run.** A basket is a `Universe` of trading
days stepped by a single clock, with one engine per symbol so participation
budgets and order books never leak across names. The invariant the sweep
enforces: a leg inside a basket must fill exactly as it does alone.

**The limiting cases are identities, not approximations.** IS at zero
urgency *is* TWAP, share for share. Adaptive at zero patience *is* TWAP.
Both are computed by TWAP's own arithmetic and checked by the sweep.

---

## Results you can reproduce

Seven demo scenarios, each a real session whose shape makes one execution
choice genuinely better than another, and each varying exactly one thing.
Every number below was measured by `dune exec bin/demo.exe`, not asserted.

**Adverse drift rewards urgency, monotonically.** NFLX 2026-07-17, a
600k-share buy, 10:00 to 11:00. The tape runs 256 bps against the buyer
inside the hour.

| config | filled | shortfall (bps) | timing cost ($) |
| --- | --- | --- | --- |
| is, urgency 4 | 100.0% | **111.5** | 404,907 |
| is, urgency 2 | 100.0% | 125.7 | 466,317 |
| twap | 100.0% | 136.7 | 510,700 |
| immediate | 6.6% | 14.9 | 0 |

**Haste has a per-share price.** GOOG 2026-07-13, the quietest day in the
catalog. Same 120k-share TWAP order, three deadlines.

| deadline | filled | impact (¢/share) |
| --- | --- | --- |
| 15:59 | **100.0%** | **4.75** |
| 12:00 | 98.3% | 7.17 |
| 10:30 | 39.7% | 8.00 |

**The passive edge.** Measured over the whole catalog, Adaptive fills
40 to 75% of its shares as a maker where every other algorithm sits at
exactly 0.0%. On the basket scenario its average shortfall is 5,900
against TWAP's 11,284. It loses to TWAP on a one-sided mid-session order in
a trend, where delay is repriced. That is the honest tradeoff, and the
demo library ends several cases with the obvious answer losing on purpose.

The full seven, with the market condition that drives each and the metric
that reveals it, are in [`demos/README.md`](demos/README.md).

---

## The browser lab

`app/ui` is a Bonsai web application compiled with js_of_ocaml. The
entire simulation, both engines included, runs client-side against an
embedded copy of the data catalog. There is no backend compute.

- A six-screen wizard: pick a day, paste or upload an alpha CSV, choose
  algorithm and engine, replay, read the results.
- The replay is a deterministic result played on a clock at 1x to 16x,
  with a zoomable SVG chart, shaded per-order windows, arrival and
  day-VWAP reference lines, per-order fill ticks, a child-order blotter
  and an event log.
- Slippage is the headline; the execution benefit is revealed only at the
  close, to avoid spoilers.
- Run history lives in the browser. Every saved run carries its complete
  config, so it can be reopened exactly, rerun with a different algorithm,
  or pinned as the baseline for a "what changed" comparison.
- Two first-class themes, `paper` and `dark`, behind a runtime toggle.
  Green and red mean good and bad execution only. Order identity gets its
  own hue palette. Buy and sell stay neutral.

```sh
dune build app/ui/main.bc.js
dune exec bin/server.exe -- 8081      # then open http://localhost:8081/
app/ui/export.sh                      # or write a static site/ for hosting
```

The hosted copy at [execution-laboratory.vercel.app](https://execution-laboratory.vercel.app/)
is exactly that export: one page and a 3 MB release bundle with all 66
sessions embedded, no backend.

The UI builds against Jane Street's preview Bonsai releases and the
OxCaml toolchain, which the public opam repository does not carry. CI
therefore covers the engine and CLI only. The engine is plain OCaml 5.2.

---

## Architecture

```
alpha CSV ─► parser ─► instructions ─► order manager ─► algorithm ─► child orders
                                                                          │
      results ◄─ report ◄─ transaction cost ◄─ portfolio ◄─ fills ◄─ fill engine
```

| library | what it owns | src | test |
| --- | --- | ---: | ---: |
| `lib/types` | Price (int cents), Side, Size, Symbol, Order_id, Bbo, Fill, Alpha_instruction | 601 | 362 |
| `lib/market` | OHLCV bars, validated 390-bar trading days, loader, day stats, multi-symbol Universe | 463 | 521 |
| `lib/alpha` | the instruction CSV parser | 92 | 169 |
| `lib/execution` | parent/child order state machines, the algorithm interface, TWAP, VWAP, POV, IS, Adaptive, Immediate | 1,343 | 1,622 |
| `lib/simulation` | the engine seam, Engine A, the per-bar driver | 580 | 474 |
| `lib/exchange` | Engine B: order book, seeded RNG, calibrated synthetic market | 781 | 589 |
| `lib/analytics` | portfolio, benchmarks, the cost decomposition, reports | 779 | 691 |
| `lib/session` | the one pipeline shared by CLI, browser, and server | 367 | 162 |
| `lib/server` | on-disk data catalog, a dependency-free HTTP server for the client | 367 | |
| `app/ui` | the Bonsai client | 10,016 | |
| `bin/` | `main` (CLI), `demo` (the seven cases), `sweep` (invariants), `server` | 1,202 | |

Every library has a `.mli` for every module, with doc comments that say
how it fits with its neighbors. Domain rules live in smart constructors:
a `Market_bar` cannot violate `low <= open, close <= high`, a
`Trading_day` cannot have anything but 390 strictly ascending bars, an
`Alpha_instruction` cannot have a deadline before its arrival.

---

## How it is known to be correct

- **185 expect and property tests**, written test-first. For anything
  with a computable answer the expected output was hand-derived before the
  implementation existed. Empty expect blocks promoted blindly are banned
  by convention.
- **The accounting identity** `gross = net + friction + opportunity` and
  the split `friction = timing + spread + impact` are enforced in integer
  cents on every grading.
- **The sweep** (`bin/sweep.exe`) runs nine scenarios, including a single
  share, a zero-length window, an impossible size, and three overlapping
  orders, across every session, every algorithm, and both engines. It
  checks fill conservation, participation caps, benchmark provenance
  per symbol, the limiting-case identities, and basket-equals-solo. Any
  violation exits non-zero, so it doubles as a regression net over the
  real data the sandboxed unit tests cannot reach.
- **Engine B's calibration invariant**: with zero client orders, the
  synthetic tape's VWAP tracks the historical day's VWAP to within 5 bps,
  on flat, trending, and wide-range days.
- **Arrival price is sampled at the first minute the algorithm could
  actually trade**, so no configuration is charged for a price it could
  never have reached.

---

## Data

Sixty-six real sessions of one-minute OHLCV bars: AAPL, GOOG, META, MSFT,
NFLX and TSLA, eleven days each in July 2026, 25,740 bars in all. One CSV
per symbol per day, validated on load. Format in
[`data/README.md`](data/README.md).

The alpha file is deliberately date-free. Instructions carry times of
day, not timestamps, so the same file replays against any session in the
catalog, which is what lets one alpha be compared across days, engines,
and algorithms with nothing else changing.

```csv
arrival_time,symbol,side,quantity,deadline
10:00:00,TSLA,BUY,5000,11:00:00
10:05:00,AAPL,SELL,4000,11:30:00
```

---

## What it does not claim

This is a market *model*, not a market. One-minute bars cannot reconstruct
the order book, so the honest description is "execution strategies run in
a synthetic market calibrated to a real historical session." The invented
spread, the participation cap and the stateless impact formula distort
every configuration identically, which means **rankings and value-add
versus a baseline are meaningful, and "your true P&L" is not**. Every
approximation is a named config knob and is documented in the module that
makes it.

Open work, in order: portfolio-level analytics for baskets (net exposure,
cross-symbol scheduling), Engine B v3 (resting client orders that deepen
the book others trade against), cross-day league tables, and an Adaptive
that reads the queue it is sitting in.

---

## Repository guide

- [`context.md`](context.md) is the full design record: every decision,
  its rationale, and the current state. Read it first if you want to
  contribute.
- [`CLAUDE.md`](CLAUDE.md) holds the code conventions (Core everywhere,
  `Or_error` at boundaries, no polymorphic compare, `_exn` suffixes,
  expect tests in `lib/<x>/test`).
- [`demos/README.md`](demos/README.md) explains the seven scenarios.
- [`docs/execlab-context.pdf`](docs/execlab-context.pdf) is a
  feature-by-feature walkthrough for a new contributor.

```sh
dune build                  # engine, CLI and (with the preview toolchain) the UI
dune runtest                # every expect test
dune fmt --auto-promote     # janestreet profile, margin 77
dune exec bin/sweep.exe     # invariants over the whole catalog
dune exec bin/demo.exe -- 4 # one demo case
```
