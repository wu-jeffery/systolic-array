`include "verilog/sys_defs.svh"

module bias_add #(
    parameter int T = `ARRAY_SIZE
)(
    input logic clock,
    input logic reset,
    input logic valid_in,
    input logic enable,
    input DATA [(T*T)-1:0] data_in,
    input DATA [T-1:0] bias_in,
    output logic valid_out,
    output DATA [(T*T)-1:0] data_out
);

    always_ff @(posedge clock) begin
        if (reset) begin
            valid_out <= 1'b0;
            data_out <= '0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                for (int row = 0; row < T; row++) begin
                    for (int col = 0; col < T; col++) begin
                        data_out[row*T + col] <= enable
                            ? data_in[row*T + col] + bias_in[col]
                            : data_in[row*T + col];
                    end
                end
            end
        end
    end

endmodule
