`include "verilog/sys_defs.svh"

module tpu #(
    parameter int T = `ARRAY_SIZE,
    parameter int K = `ARRAY_SIZE,
    parameter int MULT_PIPELINE_CYCLES = `MULT_PIPELINE_CYCLES
)(
    input logic clock,
    input logic reset,

    input logic load_activations,
    input logic load_weights,
    input DATA [T-1:0] activations_in,
    input DATA [T-1:0] weights_in,

    input logic start_compute,
    input logic fetch_result,

    output logic busy,
    output logic done,
    output logic accumulators_valid,
    output logic [(T*T)-1:0] accumulator_valid,
    output DATA [(T*T)-1:0] accumulators
);

    DATA [T-1:0] buffered_activations;
    DATA [T-1:0] buffered_weights;

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

    logic array_accumulators_valid;

    tpu_scheduler #(
        .T                   (T),
        .K                   (K),
        .MULT_PIPELINE_CYCLES(MULT_PIPELINE_CYCLES)
    ) scheduler (
        .clock            (clock),
        .reset            (reset),
        .start_compute    (start_compute),
        .busy             (busy),
        .done             (done),
        .accumulator_valid(accumulator_valid)
    );

    assign accumulators_valid = fetch_result | (|accumulator_valid);

    systolic_array #(
        .T                   (T),
        .MULT_PIPELINE_CYCLES(MULT_PIPELINE_CYCLES)
    ) array (
        .clock             (clock),
        .reset             (reset),
        .activations       (buffered_activations),
        .weights           (buffered_weights),
        .fetch_result      (fetch_result),
        .accumulators_valid(array_accumulators_valid),
        .accumulators      (accumulators)
    );

endmodule // tpu
