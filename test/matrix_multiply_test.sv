`include "verilog/sys_defs.svh"

module matrix_multiply_test ();
    localparam int T = `ARRAY_SIZE;
    localparam ADDR A_BASE = 16'd100;
    localparam ADDR B_BASE = 16'd200;
    localparam ADDR C_BASE = 16'd300;

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
    DATA expected [T*T-1:0];
    DATA observed [T*T-1:0];

    tpu_system #(
        .T(T),
        .K(T)
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

    task automatic host_read(input ADDR addr, output DATA data);
        @(negedge clock);
        host_read_req = 1'b1;
        host_read_addr = addr;
        @(negedge clock);
        host_read_req = 1'b0;
        #1;
        if (host_read_valid !== 1'b1) begin
            $display("[FAIL] host read did not return valid data for addr=%0d @t=%0t", addr, $time);
            $finish;
        end
        data = host_read_data;
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
        for (int i = 0; i < T*T; i++) begin
            expected[i] = '0;
            observed[i] = '0;
        end

        @(negedge clock);
        reset = 1'b0;

`include "build/matrix_input.svh"

        cmd.activation_base_addr = A_BASE;
        cmd.weight_base_addr = B_BASE;
        cmd.output_base_addr = C_BASE;
        cmd.m_tiles = 8'd1;
        cmd.n_tiles = 8'd1;
        cmd.k_tiles = T;

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

        for (int i = 0; i < T*T; i++) begin
            host_read(C_BASE + i, observed[i]);
        end

        $display("MATRIX_RESULT_BEGIN");
        for (int r = 0; r < T; r++) begin
            $display("%0d %0d %0d %0d",
                     observed[r*T + 0], observed[r*T + 1],
                     observed[r*T + 2], observed[r*T + 3]);
        end
        $display("MATRIX_RESULT_END");

        for (int i = 0; i < T*T; i++) begin
            if (observed[i] !== expected[i]) begin
                $display("[FAIL] C[%0d]=%0d expected=%0d", i, observed[i], expected[i]);
                $finish;
            end
        end

        $display("[PASS] matrix multiply matched expected result");
        $finish;
    end

endmodule
