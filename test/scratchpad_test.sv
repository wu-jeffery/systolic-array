`include "verilog/sys_defs.svh"

module scratchpad_test ();
    localparam int T = `ARRAY_SIZE;

    logic clock;
    logic reset;

    logic host_write_req;
    ADDR host_write_addr;
    DATA host_write_data;
    logic host_write_ready;

    logic host_read_req;
    ADDR host_read_addr;
    logic host_read_valid;
    DATA host_read_data;

    logic activation_read_req;
    ADDR activation_read_addr;
    logic activation_read_valid;
    DATA [T-1:0] activation_read_data;

    logic weight_read_req;
    ADDR weight_read_addr;
    logic weight_read_valid;
    DATA [T-1:0] weight_read_data;

    logic result_write_req;
    ADDR result_write_addr;
    logic [(T*T)-1:0] result_write_mask;
    DATA [(T*T)-1:0] result_write_data;
    logic result_write_ready;

    scratchpad #(
        .T(T)
    ) dut (
        .clock                (clock),
        .reset                (reset),
        .host_write_req       (host_write_req),
        .host_write_addr      (host_write_addr),
        .host_write_data      (host_write_data),
        .host_write_ready     (host_write_ready),
        .host_read_req        (host_read_req),
        .host_read_addr       (host_read_addr),
        .host_read_valid      (host_read_valid),
        .host_read_data       (host_read_data),
        .activation_read_req  (activation_read_req),
        .activation_read_addr (activation_read_addr),
        .activation_read_valid(activation_read_valid),
        .activation_read_data (activation_read_data),
        .weight_read_req      (weight_read_req),
        .weight_read_addr     (weight_read_addr),
        .weight_read_valid    (weight_read_valid),
        .weight_read_data     (weight_read_data),
        .result_write_req     (result_write_req),
        .result_write_addr    (result_write_addr),
        .result_write_mask    (result_write_mask),
        .result_write_data    (result_write_data),
        .result_write_ready   (result_write_ready)
    );

    always #5 clock = ~clock;

    task automatic host_write(input ADDR addr, input DATA data);
        @(negedge clock);
        host_write_req = 1'b1;
        host_write_addr = addr;
        host_write_data = data;
        @(negedge clock);
        host_write_req = 1'b0;
    endtask

    task automatic host_read_check(input ADDR addr, input DATA expected);
        @(negedge clock);
        host_read_req = 1'b1;
        host_read_addr = addr;
        @(negedge clock);
        host_read_req = 1'b0;
        #1;
        if (host_read_valid !== 1'b1 || host_read_data !== expected) begin
            $display("[FAIL] host read addr=%0d data=%0d expected=%0d valid=%0b @t=%0t",
                     addr, host_read_data, expected, host_read_valid, $time);
            $finish;
        end
    endtask

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        host_write_req = 1'b0;
        host_write_addr = '0;
        host_write_data = '0;
        host_read_req = 1'b0;
        host_read_addr = '0;
        activation_read_req = 1'b0;
        activation_read_addr = '0;
        weight_read_req = 1'b0;
        weight_read_addr = '0;
        result_write_req = 1'b0;
        result_write_addr = '0;
        result_write_mask = '0;
        result_write_data = '{default: '0};

        @(negedge clock);
        reset = 1'b0;

        host_write(16'd10, 32'd1);
        host_write(16'd11, 32'd2);
        host_write(16'd12, 32'd3);
        host_write(16'd13, 32'd4);
        host_write(16'd20, 32'd5);
        host_write(16'd21, 32'd6);
        host_write(16'd22, 32'd7);
        host_write(16'd23, 32'd8);

        @(negedge clock);
        activation_read_req = 1'b1;
        activation_read_addr = 16'd10;
        weight_read_req = 1'b1;
        weight_read_addr = 16'd20;

        @(negedge clock);
        activation_read_req = 1'b0;
        weight_read_req = 1'b0;
        #1;
        if (activation_read_valid !== 1'b1 ||
            activation_read_data[0] !== 32'd1 ||
            activation_read_data[1] !== 32'd2 ||
            activation_read_data[2] !== 32'd3 ||
            activation_read_data[3] !== 32'd4) begin
            $display("[FAIL] activation vector read failed @t=%0t", $time);
            $finish;
        end
        if (weight_read_valid !== 1'b1 ||
            weight_read_data[0] !== 32'd5 ||
            weight_read_data[1] !== 32'd6 ||
            weight_read_data[2] !== 32'd7 ||
            weight_read_data[3] !== 32'd8) begin
            $display("[FAIL] weight vector read failed @t=%0t", $time);
            $finish;
        end

        @(negedge clock);
        result_write_req = 1'b1;
        result_write_addr = 16'd100;
        result_write_mask = '0;
        result_write_mask[0] = 1'b1;
        result_write_mask[5] = 1'b1;
        result_write_data[0] = 32'd55;
        result_write_data[5] = 32'd99;

        @(negedge clock);
        result_write_req = 1'b0;

        host_read_check(16'd100, 32'd55);
        host_read_check(16'd105, 32'd99);

        $display("[PASS] scratchpad read/write smoke test");
        $finish;
    end

endmodule
