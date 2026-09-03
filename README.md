# TPU / Systolic Array Accelerator

This project is a SystemVerilog TPU-style accelerator built around a
systolic array. The goal is to develop the core hardware pieces needed for a
tiled matrix-multiply engine, then use that engine to run a simple neural
network workload.

The design is intentionally being built in layers: first the MAC and systolic
array, then input/output buffering, then command scheduling, scratchpad access,
and eventually a small software/runtime flow that can issue neural-network
operations to the hardware.

## Current Microarchitecture

The current datapath is:

```text
host/software preload port
  -> scratchpad
  -> TPU system wrapper
  -> command queue
  -> TPU controller
  -> scratchpad activation/weight vector reads
  -> input skew buffers
  -> systolic array
  -> accumulator/result valid scheduling
  -> masked result writes back to scratchpad
  -> host/software readback port
```

Main modules:

- `mac`: multiply-accumulate processing element.
- `systolic_array`: grid of MACs with activation flow across rows and weight
  flow down columns.
- `input_skew_buffer`: delays lane `i` by `i` cycles so inputs enter the array
  as a wavefront. Valid scratchpad responses stream directly into these
  buffers.
- `tpu_command_queue`: FIFO of coarse TPU commands from software or a
  testbench. It does not understand matrix multiplication timing; it only stores
  descriptors until the controller is ready to start another operation.
- `tpu_controller`: main operation state machine. It tracks the active output
  tile, issues consecutive activation/weight vector reads across K, clears the
  accumulators for each new output tile, and writes completed tiles back.
- `array_scheduler`: cycle-level timer for one streamed systolic-array run. It
  uses the runtime K length and array drain latency to determine when the full
  output tile is ready.
- `bias_add`: registered post-processing stage that adds one bias per output
  column, or passes accumulator values through when bias is disabled.
- `activation`: registered post-processing stage supporting ReLU and a
  no-activation bypass mode.
- `scratchpad`: synchronous SRAM-style local memory model with vector reads and
  masked result writes.
- `tpu`: compute core stitching the command queue, controller, buffers,
  array scheduler, and systolic array together.
- `tpu_system`: system-level wrapper that connects the TPU core to the
  scratchpad and exposes host/software ports for preloading inputs and reading
  outputs.
- `matrix_multiply_test`: testbench for one 4x4 matrix multiplication through
  the TPU system and scratchpad.
- `scripts/run_matrix_multiply.py`: Python harness that accepts two 4x4
  matrices, generates the testbench include file, launches VCS, and prints the
  result matrix.

## Control Flow

The command queue, controller, and array scheduler operate at different levels:

```text
command queue:
  stores work descriptors from software/testbench

TPU controller:
  turns one descriptor into tile-by-tile hardware actions

array scheduler:
  times one systolic-array run and marks MAC outputs valid
```

For one command, the interaction is:

```text
1. Software/testbench enqueues a TPU_CMD.
2. tpu_command_queue holds the command until the controller is idle.
3. tpu_controller dequeues the command and initializes tile counters.
4. For each output tile, the controller clears the MAC accumulators once.
5. The controller issues consecutive A/B vector reads for every K position.
6. Scratchpad responses stream through the skew buffers at one vector pair per
   cycle.
7. The first valid pair starts the array scheduler.
8. The scheduler waits for the K stream and final wavefront to drain.
9. The controller writes the complete output tile back to scratchpad.
10. The controller advances the N and M tile counters until the command is done.
```

In short:

```text
command queue = what work should run next
TPU controller = how to execute that work
array scheduler = when MAC outputs from one array run are ready
```

## Tiling Model

The accelerator is designed around tiled matrix multiplication:

```text
C[M x N] = A[M x K] * B[K x N]
```

The command descriptor stores:

- `activation_base_addr`: scratchpad base address for A tiles.
- `weight_base_addr`: scratchpad base address for B tiles.
- `bias_base_addr`: scratchpad base address for column bias vectors.
- `output_base_addr`: scratchpad base address for C tiles.
- `m_tiles`: number of output tile rows.
- `n_tiles`: number of output tile columns.
- `k_tiles`: current command-interface name for the number of scalar K steps
  accumulated into each output tile.
- `bias_enable`: enables the bias read and addition stage.
- `activation_type`: selects `ACT_NONE` or `ACT_RELU`.

For each output tile `(m_tile, n_tile)`, the controller clears the MAC
accumulators once. Every scalar K step supplies one A column vector and one B
row vector, producing an outer product that accumulates into the same output
tile. Results are written only after all K steps finish.

After a tile completes, the controller optionally reads its bias vector and
sends the tile through the fixed-latency bias and activation pipeline. Disabled
operations use registered bypasses, keeping writeback timing uniform.

### K Streaming

K streaming keeps the systolic array busy while an output tile is being
computed. Instead of starting and draining the array separately for every K
step, the controller requests K vectors on consecutive cycles. Each valid pair
streams directly into the input skew buffers, so the array receives a new outer
product every cycle. The scheduler starts on the first pair and waits only once,
after the final wavefront has crossed the array.

This design is output-stationary: partial sums remain in the MAC accumulators
while K streams through the array. The completed `T x T` tile is then written to
scratchpad in one masked write phase before the controller moves to the next
M/N tile.

For the current 4x4 matrix-multiply harness, the software/testbench writes A
into scratchpad as contiguous activation column vectors and B as contiguous
weight row vectors. The TPU command then points to those scratchpad regions and
the controller walks the K steps. The `tiling_test` exercises the same datapath
with 8x8, 12x12, and 16x16 matrices on the 4x4 array.

## Demo Harness

Run an interactive matrix multiplication with:

```bash
python3 scripts/run_matrix_multiply.py
```

The script prompts for the `M`, `K`, and `N` dimensions, then for the rows of
`A[M x K]` and `B[K x N]`. Matrices can also be supplied directly:

```bash
python3 scripts/run_matrix_multiply.py \
  "1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16" \
  "1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1"
```

To additionally run `matrix_multiply_test` and verify the result using the TPU
RTL, add `--rtl`. This requires VCS and an available license:

```bash
python3 scripts/run_matrix_multiply.py --rtl \
  "1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16" \
  "1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1"
```

Without `--rtl`, the displayed result is calculated by Python and does not
verify the SystemVerilog implementation.

With `--rtl`, dimensions that do not fill the 4x4 array are automatically
zero-padded into complete edge tiles. The harness reads back and displays only
the requested `M x N` result.

The matrix-multiply harness currently configures `bias_enable = 0` and
`activation_type = ACT_NONE`. Results still cross the registered
post-processing stages, but both stages operate as unchanged-data bypasses.
The tiling test covers 8x8, 12x12, and 16x16 bypassed operations and an 8x8
operation with per-column bias and ReLU enabled across multiple output tiles.

Demo video:

[![4x4 matrix multiplication running on the TPU testbench](https://img.youtube.com/vi/j_hraJYJYjQ/hqdefault.jpg)](https://youtu.be/j_hraJYJYjQ)

[Watch the 4x4 matrix multiplication demo](https://youtu.be/j_hraJYJYjQ).

## Near-Term Plan

The next steps are:

1. Add result buffering so completed MAC values can be packed and written back
   cleanly.
2. Add masking and zero padding for matrix dimensions that are not multiples of
   the physical array size.
3. Build a small command/runtime flow that loads weights and activations,
   launches tiled matrix multiplies, and reads results.
4. Run a simple neural network, likely a tiny MLP, using the TPU matrix engine.

The long-term direction is to make this a minimal but coherent accelerator
stack: compiler/runtime commands at the top, scratchpad-managed tile movement in
the middle, and a systolic array compute engine at the bottom.
