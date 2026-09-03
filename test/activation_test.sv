`include "verilog/sys_defs.svh"

module activation_test ();
    localparam int T = `ARRAY_SIZE;
    logic clock;
    logic reset;
    logic valid_in;
    logic valid_out;
    ACTIVATION_TYPE activation_type;
    DATA [(T*T)-1:0] data_in;
    DATA [(T*T)-1:0] data_out;

    activation #(.T(T)) dut (.*);
    always #5 clock = ~clock;

    initial begin
        clock = 0;
        reset = 1;
        valid_in = 0;
        activation_type = ACT_NONE;
        data_in = '0;
        @(negedge clock);
        reset = 0;

        data_in[0] = 32'hffffffff;
        data_in[1] = 32'd0;
        data_in[2] = 32'd7;
        activation_type = ACT_RELU;
        valid_in = 1;
        @(posedge clock);
        #1;
        if (!valid_out || data_out[0] !== 0 || data_out[1] !== 0 || data_out[2] !== 7)
            $fatal(1, "ReLU result was incorrect");

        @(negedge clock);
        data_in[0] = 32'hffffffff;
        activation_type = ACT_NONE;
        @(posedge clock);
        #1;
        if (data_out[0] !== 32'hffffffff) $fatal(1, "activation bypass was incorrect");
        $display("[PASS] ReLU and activation bypass");
        $finish;
    end
endmodule
