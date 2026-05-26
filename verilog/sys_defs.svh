`ifndef __SYS_DEFS_SVH__
`define __SYS_DEFS_SVH__

`timescale 1ns/100ps

`define ARRAY_SIZE 4
`define MULT_PIPELINE_CYCLES 0
`define ADDR_WIDTH 16
`define TILE_COUNT_WIDTH 8
`define CMD_QUEUE_DEPTH 4

typedef logic [31:0] DATA;
typedef logic [`ADDR_WIDTH-1:0] ADDR;

typedef struct packed {
    ADDR activation_base_addr;
    ADDR weight_base_addr;
    ADDR output_base_addr;
    logic [`TILE_COUNT_WIDTH-1:0] m_tiles;
    logic [`TILE_COUNT_WIDTH-1:0] n_tiles;
    logic [`TILE_COUNT_WIDTH-1:0] k_tiles;
} TPU_CMD;

typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_CLEAR,
    STATE_LOAD,
    STATE_START,
    STATE_RUN,
    STATE_ADVANCE
} STATE;


`endif // __SYS_DEFS_SVH__
