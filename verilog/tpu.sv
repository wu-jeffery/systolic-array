`include "verilog/sys_defs.svh"

module tpu #(
    parameter int T = `ARRAY_SIZE,
    parameter int K = `ARRAY_SIZE,
    parameter int MULT_PIPELINE_CYCLES = `MULT_PIPELINE_CYCLES
)(
    input logic clock,
    input logic reset,

    input logic cmd_valid,
    output logic cmd_ready,
    input TPU_CMD cmd,

    input DATA [T-1:0] activations_in,
    input logic activations_valid,
    input DATA [T-1:0] weights_in,
    input logic weights_valid,

    input logic fetch_result,

    output logic activation_read_req,
    output ADDR activation_read_addr,
    output logic weight_read_req,
    output ADDR weight_read_addr,
    output logic result_write_req,
    output ADDR result_write_addr,
    output logic [(T*T)-1:0] result_write_mask,
    output DATA [(T*T)-1:0] result_write_data,

    output logic busy,
    output logic done,
    output logic accumulators_valid,
    output logic [(T*T)-1:0] accumulator_valid,
    output DATA [(T*T)-1:0] accumulators
);

    DATA [T-1:0] buffered_activations;
    DATA [T-1:0] buffered_weights;
    DATA [T-1:0] skewed_activations;
    DATA [T-1:0] skewed_weights;
    logic load_activations;
    logic load_weights;
    logic start_compute;
    logic clear_accumulators;
    logic scheduler_busy;
    logic scheduler_done;
    logic controller_busy;
    logic controller_done;
    logic queued_cmd_valid;
    logic queued_cmd_ready;
    TPU_CMD queued_cmd;

    tpu_command_queue cmd_queue (
        .clock        (clock),
        .reset        (reset),
        .enqueue_valid(cmd_valid),
        .enqueue_ready(cmd_ready),
        .enqueue_cmd  (cmd),
        .dequeue_valid(queued_cmd_valid),
        .dequeue_ready(queued_cmd_ready),
        .dequeue_cmd  (queued_cmd)
    );

    activation_buffer #(
        .T(T)
    ) act_buffer (
        .clock          (clock),
        .reset          (reset),
        .load           (load_activations),
        .activations_in (activations_in),
        .activations_out(buffered_activations)
    );

    weight_buffer #(
        .T(T)
    ) wt_buffer (
        .clock      (clock),
        .reset      (reset),
        .load       (load_weights),
        .weights_in (weights_in),
        .weights_out(buffered_weights)
    );

    input_skew_buffer #(
        .T(T)
    ) activation_skew (
        .clock   (clock),
        .reset   (reset),
        .clear   (clear_accumulators),
        .load    (start_compute),
        .data_in (buffered_activations),
        .data_out(skewed_activations)
    );

    input_skew_buffer #(
        .T(T)
    ) weight_skew (
        .clock   (clock),
        .reset   (reset),
        .clear   (clear_accumulators),
        .load    (start_compute),
        .data_in (buffered_weights),
        .data_out(skewed_weights)
    );

    tpu_scheduler #(
        .T                   (T),
        .K                   (K),
        .MULT_PIPELINE_CYCLES(MULT_PIPELINE_CYCLES)
    ) scheduler (
        .clock            (clock),
        .reset            (reset),
        .start_compute    (start_compute),
        .busy             (scheduler_busy),
        .done             (scheduler_done),
        .accumulator_valid(accumulator_valid)
    );

    tpu_controller #(
        .T(T)
    ) controller (
        .clock              (clock),
        .reset              (reset),
        .cmd_valid          (queued_cmd_valid),
        .cmd_ready          (queued_cmd_ready),
        .cmd                (queued_cmd),
        .array_busy         (scheduler_busy),
        .array_done         (scheduler_done),
        .accumulator_valid  (accumulator_valid),
        .clear_accumulators (clear_accumulators),
        .load_activations   (load_activations),
        .load_weights       (load_weights),
        .start_compute      (start_compute),
        .activation_read_req(activation_read_req),
        .activation_read_addr(activation_read_addr),
        .activation_read_valid(activations_valid),
        .weight_read_req    (weight_read_req),
        .weight_read_addr   (weight_read_addr),
        .weight_read_valid  (weights_valid),
        .result_write_req   (result_write_req),
        .result_write_addr  (result_write_addr),
        .result_write_mask  (result_write_mask),
        .busy               (controller_busy),
        .done               (controller_done)
    );

    assign busy = controller_busy || scheduler_busy || queued_cmd_valid;
    assign done = controller_done;
    assign accumulators_valid = fetch_result | (|accumulator_valid);
    assign result_write_data = accumulators;

    systolic_array #(
        .T                   (T),
        .MULT_PIPELINE_CYCLES(MULT_PIPELINE_CYCLES)
    ) array (
        .clock             (clock),
        .reset             (reset),
        .clear_accumulators(clear_accumulators),
        .activations       (skewed_activations),
        .weights           (skewed_weights),
        .fetch_result      (fetch_result),
        .accumulators_valid(),
        .accumulators      (accumulators)
    );

endmodule // tpu
