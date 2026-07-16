# TPU / Systolic Array Accelerator

This project is a small SystemVerilog TPU-style accelerator built around a
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
  -> activation buffer / weight buffer
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
- `activation_buffer` / `weight_buffer`: stage vectors before they enter the
  array.
- `input_skew_buffer`: delays lane `i` by `i` cycles so inputs enter the array
  as a wavefront.
- `tpu_scheduler`: tracks cycle timing for one array run and produces
  per-accumulator valid bits.
- `tpu_command_queue`: FIFO of coarse TPU commands.
- `tpu_controller`: walks tiled matrix-multiply loops, controls buffer loads,
  starts array runs, clears accumulators at output-tile boundaries, and emits
  result write requests.
- `scratchpad`: synchronous SRAM-style local memory model with vector reads and
  masked result writes.
- `tpu`: compute core stitching the command queue, controller, buffers,
  scheduler, and systolic array together.
- `tpu_system`: system-level wrapper that connects the TPU core to the
  scratchpad and exposes host/software ports for preloading inputs and reading
  outputs.
- `matrix_multiply_test`: testbench for one 4x4 matrix multiplication through
  the TPU system and scratchpad.
- `scripts/run_matrix_multiply.py`: Python harness that accepts two 4x4
  matrices, generates the testbench include file, launches VCS, and prints the
  result matrix.

## Tiling Model

The accelerator is designed around tiled matrix multiplication:

```text
C[M x N] = A[M x K] * B[K x N]
```

The command descriptor stores:

- `activation_base_addr`: scratchpad base address for A tiles.
- `weight_base_addr`: scratchpad base address for B tiles.
- `output_base_addr`: scratchpad base address for C tiles.
- `m_tiles`: number of output tile rows.
- `n_tiles`: number of output tile columns.
- `k_tiles`: number of reduction tiles accumulated into each output tile.

For each output tile `(m_tile, n_tile)`, the controller clears the MAC
accumulators once, then runs through all `k_tile`s without clearing. This lets
partial products accumulate into the same output tile. Results are written only
after the final reduction tile.

For the current 4x4 matrix-multiply harness, the software/testbench writes A
into scratchpad as contiguous activation column vectors and B as contiguous
weight row vectors. The TPU command then points to those scratchpad regions and
the controller walks the reduction tiles.

## Demo Harness

A matrix multiplication demo is coming soon. The current harness entrypoint is:

```bash
python3 scripts/run_matrix_multiply.py \
  "1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16" \
  "1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1"
```

The script generates `build/matrix_input.svh`, runs the `matrix_multiply_test`
testbench, and prints the output matrix in a readable format. It is intended to
run on CAEN or another environment with VCS available.

## Near-Term Plan

The next steps are:

1. Validate the matrix multiplication demo on CAEN with VCS.
2. Expand the activation and weight buffers from single-vector staging into
   tile-streaming buffers.
3. Add result buffering so completed MAC values can be packed and written back
   cleanly.
4. Build a small command/runtime flow that loads weights and activations,
   launches tiled matrix multiplies, and reads results.
5. Run a simple neural network, likely a tiny MLP, using the TPU matrix engine.

The long-term direction is to make this a minimal but coherent accelerator
stack: compiler/runtime commands at the top, scratchpad-managed tile movement in
the middle, and a systolic array compute engine at the bottom.
