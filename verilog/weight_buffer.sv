`include "verilog/sys_defs.svh"

module weight_buffer #(
    parameter int T = `ARRAY_SIZE
)(
    input logic clock,
    input logic reset,

    input logic load,
    input DATA [T-1:0] weights_in,

    output DATA [T-1:0] weights_out
);

    always_ff @(posedge clock) begin
        if (reset) begin
            weights_out <= '0;
        end else if (load) begin
            weights_out <= weights_in;
        end
    end

endmodule
