# TPU / Systolic Array Accelerator

[**Try it yourself: set up a simulator and demo the TPU**](#try-it-yourself)

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
  -> optional bias and activation post-processing
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
9. The tile passes through the bias and activation stages.
10. The controller writes the complete output tile back to scratchpad.
11. The controller advances the N and M tile counters until the command is done.
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

## Post-Processing

Neural-network layers commonly perform more than matrix multiplication. For a
layer with bias and ReLU, this accelerator calculates:

```text
Y[row][col] = ReLU((A * B)[row][col] + bias[col])
ReLU(x)      = max(0, x)
```

Post-processing is kept outside the systolic array so the MAC cells remain
small and regular. Once an output tile is complete, its values follow this
path:

```text
systolic-array accumulators
  -> registered bias-add or bypass stage
  -> registered ReLU or bypass stage
  -> scratchpad writeback
```

The bias stage receives one `T`-element vector for an output-column tile. Bias
element `col` is added to that column in every row of the `T x T` result tile.
For a 4x4 tile, the operation is:

```text
[c00 c01 c02 c03]   [b0 b1 b2 b3]
[c10 c11 c12 c13] + [b0 b1 b2 b3]
[c20 c21 c22 c23]   [b0 b1 b2 b3]
[c30 c31 c32 c33]   [b0 b1 b2 b3]
```

Bias vectors are stored contiguously in scratchpad. The controller selects the
vector for the current output-column tile using:

```text
bias_read_addr = bias_base_addr + current_n_tile * T
```

This selects biases 0-3 for column tile 0, biases 4-7 for column tile 1, and so
on. The same vector is reused when that column tile is computed for another
output row tile. The current implementation reads the vector again for each
output tile; caching it across row tiles is a possible later optimization.

The command controls post-processing with:

```systemverilog
cmd.bias_base_addr = 16'd250;
cmd.bias_enable = 1'b1;
cmd.activation_type = ACT_RELU;
```

Set `bias_enable` to zero to prevent the bias read and bypass addition. Select
`ACT_NONE` to bypass activation:

```systemverilog
cmd.bias_enable = 1'b0;
cmd.activation_type = ACT_NONE;
```

Both stages are always registered, including during bypass. A valid signal
travels with the data through each stage, and the controller waits for
`postprocess_done` before asserting the scratchpad write request. Consequently,
enabled and bypassed operations have the same pipeline latency, and tile
counters cannot advance before their result is ready.

ReLU is inexpensive in hardware because two's-complement signed values expose
their sign in the most-significant bit. Each output only needs a sign-bit check
and a choice between the original value and zero:

```systemverilog
relu_out = data_in[31] ? 32'd0 : data_in;
```

The current post-processing path operates on the complete `T x T` tile in
parallel to match the existing wide scratchpad write interface. A future,
more SRAM-realistic implementation can place the completed tile in a result
buffer and drain it through a `T`-lane vector unit one row per cycle.

## Try It Yourself

This demo lets you send matrices through the TPU interface, see how they are
divided into tiles for the 4x4 systolic array, and inspect the resulting output.
The free Verilator flow makes the RTL simulation available without a commercial
license. University of Michigan engineering students with access to CAEN can
also use the Synopsys VCS and Verdi tools already supported by the project.

### 1. Install the prerequisites

You need Git, Python 3, and Verilator.

On macOS with [Homebrew](https://brew.sh/):

```bash
brew install verilator
```

On Ubuntu or WSL running Ubuntu:

```bash
sudo apt update
sudo apt install verilator
```

Confirm that Python and Verilator are available:

```bash
python3 --version
verilator --version
```

### 2. Download the project

```bash
git clone https://github.com/wu-jeffery/systolic-array.git
cd systolic-array
```

If you already cloned the repository, open a terminal and change into its root
directory before running the remaining commands.

### 3. Preview the TPU demo

Start the beginner-friendly prompt:

```bash
python3 scripts/run_matrix_multiply.py
```

The script prompts for the `M`, `K`, and `N` dimensions, then for the rows of
`A[M x K]` and `B[K x N]`. It displays the matrices and expected TPU output so
you can become familiar with the interface before launching an RTL simulation.

### 4. Run the real RTL simulation

Add `--rtl` and select Verilator to compile the SystemVerilog TPU, run it, and
compare its output with the expected matrix:

```bash
python3 scripts/run_matrix_multiply.py --rtl --sim verilator
```

Enter the dimensions and matrix rows when prompted. A successful run ends with:

```text
[PASS] matrix multiply matched expected result
```

You can also supply both matrices directly. Separate entries with spaces and
rows with semicolons:

```bash
python3 scripts/run_matrix_multiply.py --rtl --sim verilator \
  "1 2 3 4; 5 6 7 8; 9 10 11 12" \
  "1 2 3; 4 5 6; 7 8 9; 10 11 12"
```

The default `--sim auto` mode prefers Verilator and falls back to VCS if it is
available, so the shorter command below normally works too:

```bash
python3 scripts/run_matrix_multiply.py --rtl
```

Users with access to Synopsys VCS can select it explicitly:

```bash
python3 scripts/run_matrix_multiply.py --rtl --sim vcs \
  "1 2; 3 4" "5 6; 7 8"
```

### 5. Inspect the results

Every RTL run prints the input matrices, expected result, tiling dimensions,
simulator name, and TPU result. It also creates:

- `build/matrix_multiply.out`: simulation console output.
- `build/verilator_compile.out`: Verilator compiler output and warnings.
- `vcd/matrix_multiply.vcd`: a waveform file for a viewer such as GTKWave.

Verilator compiler warnings are kept out of the terminal during a successful
run. To display the complete compilation output while the demo runs, add
`--verbose`:

```bash
python3 scripts/run_matrix_multiply.py --rtl --sim verilator --verbose
```

If compilation fails, the relevant compiler output is always displayed even
without `--verbose`.

Without `--rtl`, the command is only a quick preview of the demo inputs and
expected output; it does not run or verify the SystemVerilog implementation.

With `--rtl`, dimensions that do not fill the 4x4 array are automatically
zero-padded into complete edge tiles. The harness reads back and displays only
the requested `M x N` result.

The matrix-multiply harness currently configures `bias_enable = 0` and
`activation_type = ACT_NONE`. Results still cross the registered
post-processing stages, but both stages operate as unchanged-data bypasses.
The tiling test covers 8x8, 12x12, and 16x16 bypassed operations and an 8x8
operation with per-column bias and ReLU enabled across multiple output tiles.

### Using Synopsys tools on U-M CAEN

University of Michigan engineering students with CAEN access can use Synopsys
VCS to run the Makefile-driven testbenches. For example, this command compiles
and runs the full TPU system testbench:

```bash
make tpu_system
```

To run the same testbench and inspect its signals in the Verdi waveform and
debugging interface, use:

```bash
make tpu_system.verdi
```

Replace `tpu_system` with another available test target such as `mac`,
`systolic_array`, `scratchpad`, `activation`, or `tiling`. For example:

```bash
make systolic_array
make systolic_array.verdi
```

The Makefile loads the required CAEN modules automatically. These commands
require a U-M CAEN environment and access to the corresponding Synopsys
licenses; everyone else can use the Verilator demo above.

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
