`include "verilog/sys_defs.svh"

module input_skew_buffer #(
    parameter int T = `ARRAY_SIZE
)(
    input logic clock,
    input logic reset,

    input logic clear,
    input logic load,
    input DATA [T-1:0] data_in,

    output DATA [T-1:0] data_out
);

    genvar lane;
    generate
        for (lane = 0; lane < T; lane++) begin : GEN_SKEW_LANE
            DATA delay_pipe [lane:0];

            always_ff @(posedge clock) begin
                if (reset || clear) begin
                    for (int i = 0; i <= lane; i++) begin
                        delay_pipe[i] <= '0;
                    end
                end else begin
                    delay_pipe[0] <= load ? data_in[lane] : '0;

                    for (int i = 1; i <= lane; i++) begin
                        delay_pipe[i] <= delay_pipe[i-1];
                    end
                end
            end

            assign data_out[lane] = delay_pipe[lane];
        end
    endgenerate

endmodule
