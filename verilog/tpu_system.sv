`include "verilog/sys_defs.svh"

module tpu_system #(
    parameter int T = `ARRAY_SIZE,
    parameter int K = `ARRAY_SIZE,
    parameter int SCRATCHPAD_DEPTH = 1024,
    parameter int MULT_PIPELINE_CYCLES = `MULT_PIPELINE_CYCLES
)(
    input logic clock,
    input logic reset,

    input logic cmd_valid,
    output logic cmd_ready,
    input TPU_CMD cmd,

    input logic host_write_req,
    input ADDR host_write_addr,
    input DATA host_write_data,
    output logic host_write_ready,

    input logic host_read_req,
    input ADDR host_read_addr,
    output logic host_read_valid,
    output DATA host_read_data,

    output logic busy,
    output logic done
);

    logic activation_read_req;
    ADDR activation_read_addr;
    logic activation_read_valid;
    DATA [T-1:0] activation_read_data;

    logic weight_read_req;
    ADDR weight_read_addr;
    logic weight_read_valid;
    DATA [T-1:0] weight_read_data;

    logic result_write_req;
    ADDR result_write_addr;
    logic [(T*T)-1:0] result_write_mask;
    DATA [(T*T)-1:0] result_write_data;
    logic result_write_ready;

    logic accumulators_valid;
    logic [(T*T)-1:0] accumulator_valid;
    DATA [(T*T)-1:0] accumulators;

    scratchpad #(
        .T(T),
        .DEPTH(SCRATCHPAD_DEPTH)
    ) spad (
        .clock                (clock),
        .reset                (reset),
        .host_write_req       (host_write_req),
        .host_write_addr      (host_write_addr),
        .host_write_data      (host_write_data),
        .host_write_ready     (host_write_ready),
        .host_read_req        (host_read_req),
        .host_read_addr       (host_read_addr),
        .host_read_valid      (host_read_valid),
        .host_read_data       (host_read_data),
        .activation_read_req  (activation_read_req),
        .activation_read_addr (activation_read_addr),
        .activation_read_valid(activation_read_valid),
        .activation_read_data (activation_read_data),
        .weight_read_req      (weight_read_req),
        .weight_read_addr     (weight_read_addr),
        .weight_read_valid    (weight_read_valid),
        .weight_read_data     (weight_read_data),
        .result_write_req     (result_write_req),
        .result_write_addr    (result_write_addr),
        .result_write_mask    (result_write_mask),
        .result_write_data    (result_write_data),
        .result_write_ready   (result_write_ready)
    );

    tpu #(
        .T                   (T),
        .K                   (K),
        .MULT_PIPELINE_CYCLES(MULT_PIPELINE_CYCLES)
    ) core (
        .clock             (clock),
        .reset             (reset),
        .cmd_valid         (cmd_valid),
        .cmd_ready         (cmd_ready),
        .cmd               (cmd),
        .activations_in    (activation_read_data),
        .activations_valid (activation_read_valid),
        .weights_in        (weight_read_data),
        .weights_valid     (weight_read_valid),
        .fetch_result      (1'b0),
        .activation_read_req(activation_read_req),
        .activation_read_addr(activation_read_addr),
        .weight_read_req   (weight_read_req),
        .weight_read_addr  (weight_read_addr),
        .result_write_req  (result_write_req),
        .result_write_addr (result_write_addr),
        .result_write_mask (result_write_mask),
        .result_write_data (result_write_data),
        .busy              (busy),
        .done              (done),
        .accumulators_valid(accumulators_valid),
        .accumulator_valid (accumulator_valid),
        .accumulators      (accumulators)
    );

endmodule
