`include "verilog/sys_defs.svh"

module bias_add_test ();
    localparam int T = `ARRAY_SIZE;
    logic clock;
    logic reset;
    logic valid_in;
    logic enable;
    logic valid_out;
    DATA [(T*T)-1:0] data_in;
    DATA [T-1:0] bias_in;
    DATA [(T*T)-1:0] data_out;

    bias_add #(.T(T)) dut (.*);
    always #5 clock = ~clock;

    initial begin
        clock = 0;
        reset = 1;
        valid_in = 0;
        enable = 0;
        data_in = '0;
        bias_in = '0;
        @(negedge clock);
        reset = 0;

        for (int row = 0; row < T; row++) begin
            for (int col = 0; col < T; col++) begin
                data_in[row*T + col] = row * 10 + col;
            end
        end
        for (int col = 0; col < T; col++) bias_in[col] = col + 1;
        enable = 1;
        valid_in = 1;
        @(posedge clock);
        #1;
        if (!valid_out) $fatal(1, "bias output was not valid");
        for (int row = 0; row < T; row++) begin
            for (int col = 0; col < T; col++) begin
                if (data_out[row*T + col] !== row * 10 + col + col + 1)
                    $fatal(1, "incorrect biased result at row=%0d col=%0d", row, col);
            end
        end
        $display("[PASS] bias add and column-wise reuse");
        $finish;
    end
endmodule
