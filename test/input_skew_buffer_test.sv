`include "verilog/sys_defs.svh"

module input_skew_buffer_test ();
    localparam int T = `ARRAY_SIZE;

    logic clock;
    logic reset;
    logic clear;
    logic load;
    DATA [T-1:0] data_in;
    DATA [T-1:0] data_out;

    input_skew_buffer #(
        .T(T)
    ) dut (
        .clock   (clock),
        .reset   (reset),
        .clear   (clear),
        .load    (load),
        .data_in (data_in),
        .data_out(data_out)
    );

    always #5 clock = ~clock;

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        clear = 1'b0;
        load = 1'b0;
        data_in = '{default: '0};

        @(negedge clock);
        reset = 1'b0;
        data_in[0] = 32'd10;
        data_in[1] = 32'd20;
        data_in[2] = 32'd30;
        data_in[3] = 32'd40;
        load = 1'b1;

        @(posedge clock);
        #1;
        if (data_out[0] !== 32'd10 || data_out[1] !== 32'd0 ||
            data_out[2] !== 32'd0 || data_out[3] !== 32'd0) begin
            $display("[FAIL] skew cycle 0 data_out=%0d,%0d,%0d,%0d",
                     data_out[0], data_out[1], data_out[2], data_out[3]);
            $finish;
        end

        @(negedge clock);
        load = 1'b0;

        @(posedge clock);
        #1;
        if (data_out[0] !== 32'd0 || data_out[1] !== 32'd20 ||
            data_out[2] !== 32'd0 || data_out[3] !== 32'd0) begin
            $display("[FAIL] skew cycle 1 data_out=%0d,%0d,%0d,%0d",
                     data_out[0], data_out[1], data_out[2], data_out[3]);
            $finish;
        end

        @(posedge clock);
        #1;
        if (data_out[0] !== 32'd0 || data_out[1] !== 32'd0 ||
            data_out[2] !== 32'd30 || data_out[3] !== 32'd0) begin
            $display("[FAIL] skew cycle 2 data_out=%0d,%0d,%0d,%0d",
                     data_out[0], data_out[1], data_out[2], data_out[3]);
            $finish;
        end

        @(posedge clock);
        #1;
        if (data_out[0] !== 32'd0 || data_out[1] !== 32'd0 ||
            data_out[2] !== 32'd0 || data_out[3] !== 32'd40) begin
            $display("[FAIL] skew cycle 3 data_out=%0d,%0d,%0d,%0d",
                     data_out[0], data_out[1], data_out[2], data_out[3]);
            $finish;
        end

        clear = 1'b1;
        @(posedge clock);
        #1;
        for (int i = 0; i < T; i++) begin
            if (data_out[i] !== '0) begin
                $display("[FAIL] skew clear failed at lane %0d", i);
                $finish;
            end
        end

        $display("[PASS] input skew buffer smoke test");
        $finish;
    end

endmodule
