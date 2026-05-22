`include "verilog/sys_defs.svh"

module systolic_array_test ();
    localparam int T = `ARRAY_SIZE;

    logic clock;
    logic reset;
    logic clear_accumulators;

    DATA [T-1:0] activations;
    DATA [T-1:0] weights;

    logic fetch_result;

    logic accumulators_valid;
    DATA [(T*T)-1:0] accumulators;

    systolic_array dut #(
        .T(T)
    )(
        .clock(clock),
        .reset(reset),
        .clear_accumulators(clear_accumulators),

        // Data
        .activations(activations),
        .weights(weights),

        // Control Signals
        .fetch_result(fetch_result),

        .accumulators_valid(accumulators_valid),
        .accumulators(accumulators)
    );

endmodule
