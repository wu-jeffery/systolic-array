`include "verilog/sys_defs.svh"

module tpu #(
    parameter int T = `ARRAY_SIZE
)(
    input logic clock,
    input logic reset,

    input logic load_activations,
    input logic load_weights,
    input DATA [T-1:0] activations_in,
    input DATA [T-1:0] weights_in,

    input logic fetch_result,

    output logic accumulators_valid,
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

    systolic_array #(
        .T(T)
    ) array (
        .clock             (clock),
        .reset             (reset),
        .activations       (buffered_activations),
        .weights           (buffered_weights),
        .fetch_result      (fetch_result),
        .accumulators_valid(accumulators_valid),
        .accumulators      (accumulators)
    );

endmodule // tpu
