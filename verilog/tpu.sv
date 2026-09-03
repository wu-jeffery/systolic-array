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
    input DATA [T-1:0] bias_in,
    input logic bias_valid,

    input logic fetch_result,

    output logic activation_read_req,
    output ADDR activation_read_addr,
    output logic weight_read_req,
    output ADDR weight_read_addr,
    output logic bias_read_req,
    output ADDR bias_read_addr,
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

    DATA [T-1:0] skewed_activations;
    DATA [T-1:0] skewed_weights;
    logic load_activations;
    logic load_weights;
    logic start_compute;
    logic [`TILE_COUNT_WIDTH-1:0] compute_length;
    logic clear_accumulators;
    logic array_scheduler_busy;
    logic array_scheduler_done;
    logic controller_busy;
    logic controller_done;
    logic queued_cmd_valid;
    logic queued_cmd_ready;
    TPU_CMD queued_cmd;
    logic postprocess_start;
    logic postprocess_done;
    logic bias_enable;
    ACTIVATION_TYPE activation_type;
    logic bias_stage_valid;
    DATA [T-1:0] bias_register;
    DATA [(T*T)-1:0] biased_results;
    DATA [(T*T)-1:0] processed_results;

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

    // Valid scratchpad responses stream directly into the skew pipelines.
    input_skew_buffer #(
        .T(T)
    ) activation_skew (
        .clock   (clock),
        .reset   (reset),
        .clear   (clear_accumulators),
        .load    (load_activations && load_weights),
        .data_in (activations_in),
        .data_out(skewed_activations)
    );

    input_skew_buffer #(
        .T(T)
    ) weight_skew (
        .clock   (clock),
        .reset   (reset),
        .clear   (clear_accumulators),
        .load    (load_activations && load_weights),
        .data_in (weights_in),
        .data_out(skewed_weights)
    );

    array_scheduler #(
        .T                   (T),
        .MULT_PIPELINE_CYCLES(MULT_PIPELINE_CYCLES)
    ) array_sched (
        .clock            (clock),
        .reset            (reset),
        .start_compute    (start_compute),
        .compute_length   (compute_length),
        .busy             (array_scheduler_busy),
        .done             (array_scheduler_done),
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
        .array_busy         (array_scheduler_busy),
        .array_done         (array_scheduler_done),
        .clear_accumulators (clear_accumulators),
        .load_activations   (load_activations),
        .load_weights       (load_weights),
        .start_compute      (start_compute),
        .compute_length     (compute_length),
        .activation_read_req(activation_read_req),
        .activation_read_addr(activation_read_addr),
        .activation_read_valid(activations_valid),
        .weight_read_req    (weight_read_req),
        .weight_read_addr   (weight_read_addr),
        .weight_read_valid  (weights_valid),
        .bias_read_req      (bias_read_req),
        .bias_read_addr     (bias_read_addr),
        .bias_read_valid    (bias_valid),
        .postprocess_start  (postprocess_start),
        .postprocess_done   (postprocess_done),
        .bias_enable        (bias_enable),
        .activation_type    (activation_type),
        .result_write_req   (result_write_req),
        .result_write_addr  (result_write_addr),
        .result_write_mask  (result_write_mask),
        .busy               (controller_busy),
        .done               (controller_done)
    );

    assign busy = controller_busy || array_scheduler_busy || queued_cmd_valid;
    assign done = controller_done;
    assign accumulators_valid = fetch_result | (|accumulator_valid);
    assign result_write_data = processed_results;

    always_ff @(posedge clock) begin
        if (reset) begin
            bias_register <= '0;
        end else if (bias_valid) begin
            bias_register <= bias_in;
        end
    end

    bias_add #(
        .T(T)
    ) bias_unit (
        .clock    (clock),
        .reset    (reset),
        .valid_in (postprocess_start),
        .enable   (bias_enable),
        .data_in  (accumulators),
        .bias_in  (bias_register),
        .valid_out(bias_stage_valid),
        .data_out (biased_results)
    );

    activation #(
        .T(T)
    ) activation_unit (
        .clock          (clock),
        .reset          (reset),
        .valid_in       (bias_stage_valid),
        .activation_type(activation_type),
        .data_in        (biased_results),
        .valid_out      (postprocess_done),
        .data_out       (processed_results)
    );

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
