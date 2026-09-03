`include "verilog/sys_defs.svh"

module activation #(
    parameter int T = `ARRAY_SIZE
)(
    input logic clock,
    input logic reset,
    input logic valid_in,
    input ACTIVATION_TYPE activation_type,
    input DATA [(T*T)-1:0] data_in,
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
                for (int i = 0; i < T*T; i++) begin
                    case (activation_type)
                        ACT_RELU: data_out[i] <= data_in[i][31] ? '0 : data_in[i];
                        default:  data_out[i] <= data_in[i];
                    endcase
                end
            end
        end
    end

endmodule
