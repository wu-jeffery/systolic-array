`include "verilog/sys_defs.svh"

module systolic_array #(
    parameter int T = 4,
    parameter int MULT_PIPELINE_CYCLES = `MULT_PIPELINE_CYCLES
)(
    input logic clock,
    input logic reset,
    input logic clear_accumulators,

    // Data
    input DATA [T-1:0] activations,
    input DATA [T-1:0] weights,

    // Control Signals
    input logic fetch_result,
    
    output logic accumulators_valid,
    output DATA [(T*T)-1:0] accumulators
);
    DATA [T-1:0][T:0] a_wire; // activation wires
    DATA [T:0][T-1:0] w_wire; // weight wires

    genvar r, c;
    generate
        for (r = 0; r < T; r++) begin : GEN_A_EDGE
            assign a_wire[r][0] = activations[r];
        end
    endgenerate

    // Drive top edge.
    generate
        for (c = 0; c < T; c++) begin : GEN_W_EDGE
            assign w_wire[0][c] = weights[c];
        end
    endgenerate

    assign accumulators_valid = fetch_result;

    generate
      for (r = 0; r < T; r++) begin : GEN_ROWS
        for (c = 0; c < T; c++) begin : GEN_COLS

          mac #(
            .MULT_PIPELINE_CYCLES(MULT_PIPELINE_CYCLES)
          ) u_mac (
            .clock        (clock),
            .reset        (reset),
            .clear_accumulator(clear_accumulators),
            .in_activation(a_wire[r][c]),
            .in_weight    (w_wire[r][c]),
            .out_activation(a_wire[r][c+1]),
            .out_weight   (w_wire[r+1][c]),
            .accumulator  (accumulators[r*T + c])
          );

        end
      end
    endgenerate

endmodule
