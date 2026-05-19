`include "verilog/sys_defs.svh"

module systolic_array_test ();
    logic clock;
    logic reset;

    DATA [T-1:0] activations;
    DATA [T-1:0] weights;

    logic fetch_result;

    logic accummulators_valid;
    DATA [(T*T)-1: 0] accummulators;

    systolic_array dut #(
        .T(`ARRAY_SIZE)
    )(
        .clock(clock),
        .reset(reset),

        // Data
        .activations(activations),
        .weights(weights),

        // Control Signals
        .fetch_result(fetch_result),

        .accummulators_valid(accummulators_valid),
        .accummulators(accummulators)
    );

endmodule
