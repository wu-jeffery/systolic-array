`include "verilog/sys_defs.svh"

// Systolic Array Multiply Accumulate Unit
module mac #(
    parameter int MULT_PIPELINE_CYCLES = `MULT_PIPELINE_CYCLES
)(
    input logic clock,
    input logic reset,

    input DATA in_activation,
    input DATA in_weight,
    output DATA out_activation,
    output DATA out_weight,

    output DATA accumulator
);
    DATA n_accumulator;
    DATA n_out_activation;
    DATA n_out_weight;

    assign n_out_activation = in_activation;
    assign n_out_weight = in_weight;
    assign n_accumulator = accumulator + (in_activation * in_weight); // TODO This will change if we want to do FP

    always_ff @(posedge clock) begin 
        if(reset) begin 
            accumulator <= '0;
            out_weight <= '0;
            out_activation <= '0;
        end else begin 
            accumulator <= n_accumulator;
            out_weight <= n_out_weight;
            out_activation <= n_out_activation;
        end
    end
endmodule
