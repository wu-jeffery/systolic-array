`include "verilog/sys_defs.svh"

module tpu_system_test ();
    localparam int T = `ARRAY_SIZE;

    logic clock;
    logic reset;

    logic cmd_valid;
    logic cmd_ready;
    TPU_CMD cmd;

    logic host_write_req;
    ADDR host_write_addr;
    DATA host_write_data;
    logic host_write_ready;

    logic host_read_req;
    ADDR host_read_addr;
    logic host_read_valid;
    DATA host_read_data;

    logic busy;
    logic done;

    tpu_system #(
        .T(T)
    ) dut (
        .clock           (clock),
        .reset           (reset),
        .cmd_valid       (cmd_valid),
        .cmd_ready       (cmd_ready),
        .cmd             (cmd),
        .host_write_req  (host_write_req),
        .host_write_addr (host_write_addr),
        .host_write_data (host_write_data),
        .host_write_ready(host_write_ready),
        .host_read_req   (host_read_req),
        .host_read_addr  (host_read_addr),
        .host_read_valid (host_read_valid),
        .host_read_data  (host_read_data),
        .busy            (busy),
        .done            (done)
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

    task automatic host_read_check_nonzero(input ADDR addr);
        @(negedge clock);
        host_read_req = 1'b1;
        host_read_addr = addr;
        @(negedge clock);
        host_read_req = 1'b0;
        #1;
        if (host_read_valid !== 1'b1 || host_read_data === '0) begin
            $display("[FAIL] expected nonzero scratchpad output at addr=%0d data=%0d valid=%0b @t=%0t",
                     addr, host_read_data, host_read_valid, $time);
            $finish;
        end
    endtask

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        cmd_valid = 1'b0;
        cmd = '0;
        host_write_req = 1'b0;
        host_write_addr = '0;
        host_write_data = '0;
        host_read_req = 1'b0;
        host_read_addr = '0;

        @(negedge clock);
        reset = 1'b0;

        host_write(16'd100, 32'd2);
        host_write(16'd101, 32'd3);
        host_write(16'd102, 32'd4);
        host_write(16'd103, 32'd5);
        host_write(16'd200, 32'd7);
        host_write(16'd201, 32'd11);
        host_write(16'd202, 32'd13);
        host_write(16'd203, 32'd17);

        cmd.activation_base_addr = 16'd100;
        cmd.weight_base_addr = 16'd200;
        cmd.output_base_addr = 16'd300;
        cmd.m_tiles = 8'd1;
        cmd.n_tiles = 8'd1;
        cmd.k_tiles = 8'd1;

        @(negedge clock);
        cmd_valid = 1'b1;
        @(posedge clock);
        #1;
        if (cmd_ready !== 1'b1) begin
            $display("[FAIL] tpu_system command queue was not ready @t=%0t", $time);
            $finish;
        end

        @(negedge clock);
        cmd_valid = 1'b0;

        wait (done);
        host_read_check_nonzero(16'd300);

        $display("[PASS] TPU system scratchpad write smoke test");
        $finish;
    end

endmodule
