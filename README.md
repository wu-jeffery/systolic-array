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
- `tpu_command_queue`: FIFO of coarse TPU commands from software or a
  testbench. It does not understand matrix multiplication timing; it only stores
  descriptors until the controller is ready to start another operation.
- `tpu_controller`: main operation state machine. It pops one command from the
  queue, tracks the active `m_tile`, `n_tile`, and `k_tile`, requests
  activation/weight vectors from scratchpad, waits for read-valid responses,
  loads the input buffers, clears accumulators when starting a new output tile,
  starts each array run, and emits result write requests.
- `tpu_scheduler`: cycle-level timer for one systolic-array run. After
  `start_compute`, it counts cycles and produces per-accumulator valid bits so
  the controller knows which MAC outputs are ready to write.
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

## Control Flow

The command queue, controller, and scheduler operate at different levels:

```text
command queue:
  stores work descriptors from software/testbench

TPU controller:
  turns one descriptor into tile-by-tile hardware actions

TPU scheduler:
  times one systolic-array run and marks MAC outputs valid
```

For one command, the interaction is:

```text
1. Software/testbench enqueues a TPU_CMD.
2. tpu_command_queue holds the command until the controller is idle.
3. tpu_controller dequeues the command and initializes tile counters.
4. For each output tile, the controller clears MAC accumulators once.
5. For each reduction tile, the controller requests A/B vectors from scratchpad.
6. When read-valid returns, the controller loads the activation/weight buffers.
7. The controller pulses start_compute.
8. tpu_scheduler counts array cycles and raises accumulator_valid bits.
9. On the final k_tile, the controller turns those valid bits into masked result
   writes.
10. The controller advances k_tile, n_tile, and m_tile until the command is done.
```

In short:

```text
command queue = what work should run next
TPU controller = how to execute that work
TPU scheduler = when MAC outputs from one array run are ready
```

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
