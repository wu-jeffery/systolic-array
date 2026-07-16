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
command queue
  -> TPU controller
  -> scratchpad-style activation/weight requests
  -> activation buffer / weight buffer
  -> input skew buffers
  -> systolic array
  -> accumulator/result valid scheduling
  -> result write request back toward scratchpad
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
- `tpu`: top-level module stitching the command queue, controller, buffers,
  scheduler, and systolic array together.

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

## Near-Term Plan

The next steps are:

1. Connect the TPU controller to the scratchpad using real read-valid/write-ready
   handshakes.
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
