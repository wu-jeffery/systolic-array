`include "verilog/sys_defs.svh"

module tiling_test ();
    localparam int T = `ARRAY_SIZE;
    localparam int MAX_MATRIX_SIZE = 2 * T;
    localparam ADDR A_BASE = 16'd0;
    localparam ADDR B_BASE = A_BASE + (MAX_MATRIX_SIZE * MAX_MATRIX_SIZE);
    localparam ADDR C_BASE = B_BASE + (MAX_MATRIX_SIZE * MAX_MATRIX_SIZE);
    localparam ADDR BIAS_BASE = C_BASE + (MAX_MATRIX_SIZE * MAX_MATRIX_SIZE);
    localparam int SCRATCHPAD_DEPTH = BIAS_BASE + MAX_MATRIX_SIZE + 16;

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

    DATA matrix_a [MAX_MATRIX_SIZE-1:0][MAX_MATRIX_SIZE-1:0];
    DATA matrix_b [MAX_MATRIX_SIZE-1:0][MAX_MATRIX_SIZE-1:0];
    DATA biases [MAX_MATRIX_SIZE-1:0];
    DATA expected [MAX_MATRIX_SIZE-1:0][MAX_MATRIX_SIZE-1:0];
    DATA observed [MAX_MATRIX_SIZE-1:0][MAX_MATRIX_SIZE-1:0];
    logic postprocessing_expected;

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
        if (!reset && dut.bias_read_req && !postprocessing_expected) begin
            $fatal(1, "tiling bypass case unexpectedly requested bias data");
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
            $display("[FAIL] no scratchpad response for address %0d @t=%0t", addr, $time);
            $finish;
        end
        data = host_read_data;
    endtask

    function automatic ADDR a_vector_addr(input int matrix_size, input int mt, input int k);
        a_vector_addr = A_BASE + (((mt * matrix_size) + k) * T);
    endfunction

    function automatic ADDR b_vector_addr(input int n_tiles, input int k, input int nt);
        b_vector_addr = B_BASE + (((k * n_tiles) + nt) * T);
    endfunction

    function automatic ADDR c_element_addr(input int n_tiles, input int row, input int col);
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
                           + (((mt * n_tiles) + nt) * T * T)
                           + (local_row * T)
                           + local_col;
        end
    endfunction

    task automatic run_tiling_case(input int matrix_size, input logic enable_postprocessing);
        int m_tiles;
        int n_tiles;
        int errors;
        DATA sum;
        begin
            m_tiles = matrix_size / T;
            n_tiles = matrix_size / T;

            $display("\n[TILING] Starting %0dx%0d matrix multiplication as %0d output tiles (%s)",
                     matrix_size, matrix_size, m_tiles * n_tiles,
                     enable_postprocessing ? "bias + ReLU" : "post-processing bypass");
            postprocessing_expected = enable_postprocessing;

            // Non-symmetric values expose row, column, and tile-order mistakes.
            for (int row = 0; row < matrix_size; row++) begin
                for (int col = 0; col < matrix_size; col++) begin
                    matrix_a[row][col] = (row * matrix_size) + col + 1;
                    matrix_b[row][col] = ((row + 1) * 3) + (col + 1);
                    expected[row][col] = '0;
                    observed[row][col] = '0;
                end
            end


            // Biases are contiguous by output column, so each N tile reads T
            // adjacent values. Large negative biases exercise ReLU as well as
            // bias-vector selection across multiple N tiles.
            for (int col = 0; col < matrix_size; col++) begin
                biases[col] = (col % 2 == 0) ? -(32'sd1000 + col) : col + 1;
                if (enable_postprocessing) begin
                    host_write(BIAS_BASE + col, biases[col]);
                end
            end

            for (int row = 0; row < matrix_size; row++) begin
                for (int col = 0; col < matrix_size; col++) begin
                    sum = '0;
                    for (int k = 0; k < matrix_size; k++) begin
                        sum = sum + (matrix_a[row][k] * matrix_b[k][col]);
                    end
                    if (enable_postprocessing) begin
                        sum = sum + biases[col];
                        if (sum[31]) begin
                            sum = '0;
                        end
                    end
                    expected[row][col] = sum;
                end
            end

            // A is packed as T-row column vectors: A[mt*T + lane][k].
            for (int mt = 0; mt < m_tiles; mt++) begin
                for (int k = 0; k < matrix_size; k++) begin
                    for (int lane = 0; lane < T; lane++) begin
                        host_write(a_vector_addr(matrix_size, mt, k) + lane,
                                   matrix_a[(mt * T) + lane][k]);
                    end
                end
            end

            // B is packed as T-column row vectors: B[k][nt*T + lane].
            for (int k = 0; k < matrix_size; k++) begin
                for (int nt = 0; nt < n_tiles; nt++) begin
                    for (int lane = 0; lane < T; lane++) begin
                        host_write(b_vector_addr(n_tiles, k, nt) + lane,
                                   matrix_b[k][(nt * T) + lane]);
                    end
                end
            end

            cmd.activation_base_addr = A_BASE;
            cmd.weight_base_addr = B_BASE;
            cmd.bias_base_addr = BIAS_BASE;
            cmd.output_base_addr = C_BASE;
            cmd.m_tiles = m_tiles;
            cmd.n_tiles = n_tiles;
            // Functional tiling currently processes one scalar K step per run.
            cmd.k_tiles = matrix_size;
            cmd.bias_enable = enable_postprocessing;
            cmd.activation_type = enable_postprocessing ? ACT_RELU : ACT_NONE;

            @(negedge clock);
            cmd_valid = 1'b1;
            @(negedge clock);
            cmd_valid = 1'b0;

            fork
                begin
                    wait (done);
                end
                begin
                    repeat (20000) @(posedge clock);
                    $display("[FAIL] timed out waiting for %0dx%0d multiplication",
                             matrix_size, matrix_size);
                    $finish;
                end
            join_any
            disable fork;

            for (int row = 0; row < matrix_size; row++) begin
                for (int col = 0; col < matrix_size; col++) begin
                    host_read(c_element_addr(n_tiles, row, col), observed[row][col]);
                end
            end

            if (enable_postprocessing) begin
                $display("\n[TILING] Matrix A:");
                for (int row = 0; row < matrix_size; row++) begin
                    $write("  [");
                    for (int col = 0; col < matrix_size; col++) begin
                        $write(" %0d", matrix_a[row][col]);
                    end
                    $display(" ]");
                end

                $display("[TILING] Matrix B:");
                for (int row = 0; row < matrix_size; row++) begin
                    $write("  [");
                    for (int col = 0; col < matrix_size; col++) begin
                        $write(" %0d", matrix_b[row][col]);
                    end
                    $display(" ]");
                end

                $write("[TILING] Column bias = [");
                for (int col = 0; col < matrix_size; col++) begin
                    $write(" %0d", biases[col]);
                end
                $display(" ]");
                $display("[TILING] Operation: C = ReLU((A x B) + column_bias)");

                $display("[TILING] Raw A x B:");
                for (int row = 0; row < matrix_size; row++) begin
                    $write("  [");
                    for (int col = 0; col < matrix_size; col++) begin
                        sum = '0;
                        for (int k = 0; k < matrix_size; k++) begin
                            sum = sum + (matrix_a[row][k] * matrix_b[k][col]);
                        end
                        $write(" %0d", sum);
                    end
                    $display(" ]");
                end

                $display("[TILING] After bias, before ReLU:");
                for (int row = 0; row < matrix_size; row++) begin
                    $write("  [");
                    for (int col = 0; col < matrix_size; col++) begin
                        sum = biases[col];
                        for (int k = 0; k < matrix_size; k++) begin
                            sum = sum + (matrix_a[row][k] * matrix_b[k][col]);
                        end
                        $write(" %0d", sum);
                    end
                    $display(" ]");
                end

                $display("[TILING] Expected C:");
                for (int row = 0; row < matrix_size; row++) begin
                    $write("  [");
                    for (int col = 0; col < matrix_size; col++) begin
                        $write(" %0d", expected[row][col]);
                    end
                    $display(" ]");
                end

                $display("[TILING] Observed TPU C:");
                for (int row = 0; row < matrix_size; row++) begin
                    $write("  [");
                    for (int col = 0; col < matrix_size; col++) begin
                        $write(" %0d", observed[row][col]);
                    end
                    $display(" ]");
                end
            end

            errors = 0;
            for (int row = 0; row < matrix_size; row++) begin
                for (int col = 0; col < matrix_size; col++) begin
                    if (observed[row][col] !== expected[row][col]) begin
                        $display("[FAIL] %0dx%0d C[%0d][%0d]: expected %0d, got %0d",
                                 matrix_size, matrix_size, row, col,
                                 expected[row][col], observed[row][col]);
                        errors++;
                    end
                end
            end

            if (errors != 0) begin
                $display("[FAIL] %0dx%0d tiling case had %0d errors",
                         matrix_size, matrix_size, errors);
                $finish;
            end

            $display("[PASS] %0dx%0d multiply completed as %0d %0dx%0d output tiles",
                     matrix_size, matrix_size, m_tiles * n_tiles, T, T);
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

        postprocessing_expected = 1'b0;

        run_tiling_case(T, 1'b0);
        run_tiling_case(2 * T, 1'b0);
        run_tiling_case(T, 1'b1);

        $display("\n[PASS] all functional tiling cases passed");
        $finish;
    end

endmodule
