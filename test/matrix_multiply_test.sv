`include "verilog/sys_defs.svh"
`include "build/matrix_config.svh"

module matrix_multiply_test ();
    localparam int T = `ARRAY_SIZE;
    localparam int M = `MATRIX_M;
    localparam int K_SIZE = `MATRIX_K;
    localparam int N = `MATRIX_N;
    localparam int PADDED_M = `PADDED_M;
    localparam int PADDED_N = `PADDED_N;
    localparam int M_TILES = PADDED_M / T;
    localparam int N_TILES = PADDED_N / T;
    localparam ADDR A_BASE = 16'd100;
    localparam ADDR B_BASE = A_BASE + (PADDED_M * K_SIZE);
    localparam ADDR C_BASE = B_BASE + (K_SIZE * PADDED_N);
    localparam int SCRATCHPAD_DEPTH = C_BASE + (PADDED_M * PADDED_N) + 16;

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
    DATA expected [M*N-1:0];
    DATA observed [M*N-1:0];

    tpu_system #(
        .T(T),
        .K(T),
        .SCRATCHPAD_DEPTH(SCRATCHPAD_DEPTH)
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

    always @(posedge clock) begin
        if (!reset && dut.bias_read_req) begin
            $fatal(1, "plain matrix multiply unexpectedly requested bias data");
        end
    end

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

    function automatic ADDR c_element_addr(input int row, input int col);
        int mt;
        int nt;
        int local_row;
        int local_col;
        begin
            mt = row / T;
            nt = col / T;
            local_row = row % T;
            local_col = col % T;
            c_element_addr = C_BASE
                           + (((mt * N_TILES) + nt) * T * T)
                           + (local_row * T)
                           + local_col;
        end
    endfunction

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
        for (int i = 0; i < M*N; i++) begin
            expected[i] = '0;
            observed[i] = '0;
        end

        @(negedge clock);
        reset = 1'b0;

`include "build/matrix_input.svh"

        cmd.activation_base_addr = A_BASE;
        cmd.weight_base_addr = B_BASE;
        cmd.output_base_addr = C_BASE;
        cmd.m_tiles = M_TILES;
        cmd.n_tiles = N_TILES;
        cmd.k_tiles = K_SIZE;
        // Plain matrix multiplication uses the registered post-processing
        // path in bypass mode. No bias read is issued and ReLU is disabled.
        cmd.bias_base_addr = '0;
        cmd.bias_enable = 1'b0;
        cmd.activation_type = ACT_NONE;

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

        for (int row = 0; row < M; row++) begin
            for (int col = 0; col < N; col++) begin
                host_read(c_element_addr(row, col), observed[row*N + col]);
            end
        end

        $display("MATRIX_RESULT_BEGIN");
        for (int row = 0; row < M; row++) begin
            for (int col = 0; col < N; col++) begin
                $write("%0d%s", observed[row*N + col], col + 1 == N ? "" : " ");
            end
            $display("");
        end
        $display("MATRIX_RESULT_END");

        for (int i = 0; i < M*N; i++) begin
            if (observed[i] !== expected[i]) begin
                $display("[FAIL] C[%0d]=%0d expected=%0d", i, observed[i], expected[i]);
                $finish;
            end
        end

        $display("[PASS] matrix multiply matched expected result");
        $finish;
    end

endmodule
