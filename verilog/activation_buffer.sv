`include "verilog/sys_defs.svh"

module activation_buffer #(
    parameter int T = `ARRAY_SIZE
)(
    input logic clock,
    input logic reset,

    input logic load,
    input DATA [T-1:0] activations_in,

    output DATA [T-1:0] activations_out
);

    always_ff @(posedge clock) begin
        if (reset) begin
            activations_out <= '0;
        end else if (load) begin
            activations_out <= activations_in;
        end
    end

endmodule
