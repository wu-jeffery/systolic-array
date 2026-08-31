`include "verilog/sys_defs.svh"

module tpu_test ();
    localparam int T = `ARRAY_SIZE;

    logic clock;
    logic reset;
    logic cmd_valid;
    logic cmd_ready;
    TPU_CMD cmd;
    logic fetch_result;

    DATA [T-1:0] activations_in;
    logic activations_valid;
    DATA [T-1:0] weights_in;
    logic weights_valid;
    logic activation_read_req;
    ADDR activation_read_addr;
    logic weight_read_req;
    ADDR weight_read_addr;
    logic result_write_req;
    ADDR result_write_addr;
    logic [(T*T)-1:0] result_write_mask;
    DATA [(T*T)-1:0] result_write_data;
    logic busy;
    logic done;
    logic accumulators_valid;
    logic [(T*T)-1:0] accumulator_valid;
    DATA [(T*T)-1:0] accumulators;
    DATA matrix_a [T-1:0][T-1:0];
    DATA matrix_b [T-1:0][T-1:0];
    string dumpfile;

    tpu #(
        .T(T)
    ) dut (
        .clock               (clock),
        .reset               (reset),
        .cmd_valid           (cmd_valid),
        .cmd_ready           (cmd_ready),
        .cmd                 (cmd),
        .activations_in      (activations_in),
        .activations_valid   (activations_valid),
        .weights_in          (weights_in),
        .weights_valid       (weights_valid),
        .fetch_result        (fetch_result),
        .activation_read_req (activation_read_req),
        .activation_read_addr(activation_read_addr),
        .weight_read_req     (weight_read_req),
        .weight_read_addr    (weight_read_addr),
        .result_write_req    (result_write_req),
        .result_write_addr   (result_write_addr),
        .result_write_mask   (result_write_mask),
        .result_write_data   (result_write_data),
        .busy                (busy),
        .done                (done),
        .accumulators_valid  (accumulators_valid),
        .accumulator_valid   (accumulator_valid),
        .accumulators        (accumulators)
    );

    always #5 clock = ~clock;

    task automatic print_input_operation;
        $display("\n[TPU] Matrix operation for this test:");
        $display("      A (%0dx%0d):", T, T);
        for (int r = 0; r < T; r++) begin
            $write("      [");
            for (int c = 0; c < T; c++) begin
                $write(" %0d", matrix_a[r][c]);
            end
            $display(" ]");
        end
        $display("      B (%0dx%0d):", T, T);
        for (int r = 0; r < T; r++) begin
            $write("      [");
            for (int c = 0; c < T; c++) begin
                $write(" %0d", matrix_b[r][c]);
            end
            $display(" ]");
        end
        $display("      Computing C = A x B using %0d accumulated outer products\n", T);
    endtask

    task automatic check_result_matrix;
        DATA expected;
        int errors;

        errors = 0;
        for (int r = 0; r < T; r++) begin
            for (int c = 0; c < T; c++) begin
                expected = '0;
                for (int k = 0; k < T; k++) begin
                    expected = expected + (matrix_a[r][k] * matrix_b[k][c]);
                end
                if (accumulators[r*T + c] !== expected) begin
                    $display("[FAIL] C[%0d][%0d]: expected %0d, got %0d",
                             r, c, expected, accumulators[r*T + c]);
                    errors++;
                end
            end
        end

        if (errors != 0) begin
            $display("[FAIL] 4x4 matrix multiplication had %0d incorrect elements", errors);
            $finish;
        end
    endtask

    task automatic print_result_matrix(input string label);
        $display("[TPU] %s C (%0dx%0d):", label, T, T);
        for (int r = 0; r < T; r++) begin
            $write("      [");
            for (int c = 0; c < T; c++) begin
                $write(" %0d", accumulators[r*T + c]);
            end
            $display(" ]");
        end
    endtask

    always @(posedge clock) begin
        if (!reset && result_write_req) begin
            $display("[TPU] Writing completed result elements to scratchpad base address %0d:",
                     result_write_addr);
            for (int r = 0; r < T; r++) begin
                for (int c = 0; c < T; c++) begin
                    if (result_write_mask[r*T + c]) begin
                        $display("      C[%0d][%0d] = %0d", r, c,
                                 result_write_data[r*T + c]);
                    end
                end
            end
        end
    end

    task automatic wait_cycles(input int max_cycles, input string tag);
        for (int i = 0; i < max_cycles; i++) begin
            @(posedge clock);
            if (activation_read_req || weight_read_req || result_write_req ||
                accumulators_valid || done) begin
                $display("[DBG] %s cycle=%0d t=%0t act_req=%0b act_addr=%0d wt_req=%0b wt_addr=%0d valid=%h wr_req=%0b wr_addr=%0d done=%0b busy=%0b",
                         tag, i, $time, activation_read_req, activation_read_addr,
                         weight_read_req, weight_read_addr, accumulator_valid,
                         result_write_req, result_write_addr, done, busy);
            end
        end
        $display("[FAIL] timeout waiting for %s @t=%0t", tag, $time);
        $finish;
    endtask

    task automatic wait_for_activation_request(input int max_cycles);
        for (int i = 0; i < max_cycles; i++) begin
            @(posedge clock);
            #1;
            if (activation_read_req) begin
                $display("[DBG] saw activation/weight request @t=%0t act_addr=%0d wt_addr=%0d",
                         $time, activation_read_addr, weight_read_addr);
                return;
            end
        end
        wait_cycles(0, "activation request");
    endtask

    task automatic wait_for_result_write(input int max_cycles);
        for (int i = 0; i < max_cycles; i++) begin
            @(posedge clock);
            #1;
            if (result_write_req) begin
                $display("[DBG] saw result write @t=%0t addr=%0d mask=%h done=%0b",
                         $time, result_write_addr, result_write_mask, done);
                return;
            end
        end
        wait_cycles(0, "result write");
    endtask

    task automatic wait_for_done(input int max_cycles);
        if (done) begin
            return;
        end

        for (int i = 0; i < max_cycles; i++) begin
            @(posedge clock);
            #1;
            if (done) begin
                $display("[DBG] saw done @t=%0t", $time);
                return;
            end
        end
        wait_cycles(0, "done");
    endtask

    initial begin
        if (!$value$plusargs("dumpfile=%s", dumpfile)) begin
            dumpfile = "tpu.vcd";
        end
        $dumpfile(dumpfile);
        $dumpvars(0, tpu_test);

        clock = 1'b0;
        reset = 1'b1;
        cmd_valid = 1'b0;
        fetch_result = 1'b0;
        activations_valid = 1'b0;
        weights_valid = 1'b0;
        activations_in = '{default: '0};
        weights_in = '{default: '0};
        cmd = '0;

        for (int r = 0; r < T; r++) begin
            for (int c = 0; c < T; c++) begin
                matrix_a[r][c] = (r * T) + c + 1;
                matrix_b[r][c] = (r * T) + c + 17;
            end
        end

        @(negedge clock);
        reset = 1'b0;

        cmd.activation_base_addr = 16'd100;
        cmd.weight_base_addr = 16'd200;
        cmd.output_base_addr = 16'd300;
        cmd.m_tiles = 8'd1;
        cmd.n_tiles = 8'd1;
        cmd.k_tiles = T;
        print_input_operation();
        cmd_valid = 1'b1;

        @(posedge clock);
        #1;
        if (cmd_ready !== 1'b1) begin
            $display("[FAIL] TPU command queue was not ready @t=%0t", $time);
            $finish;
        end

        @(negedge clock);
        cmd_valid = 1'b0;

        for (int k = 0; k < T; k++) begin
            wait_for_activation_request(100);
            if (activation_read_addr !== 16'd100 + (k * T) ||
                weight_read_addr !== 16'd200 + (k * T)) begin
                $display("[FAIL] reduction k=%0d requested act_addr=%0d wt_addr=%0d",
                         k, activation_read_addr, weight_read_addr);
                $finish;
            end

            for (int lane = 0; lane < T; lane++) begin
                activations_in[lane] = matrix_a[lane][k];
                weights_in[lane] = matrix_b[k][lane];
            end
            $display("[TPU] Reduction k=%0d: loading A[:,%0d] and B[%0d,:]", k, k, k);

            @(negedge clock);
            activations_valid = 1'b1;
            weights_valid = 1'b1;
            wait (dut.load_activations && dut.load_weights);
            @(negedge clock);
            activations_valid = 1'b0;
            weights_valid = 1'b0;
        end

        wait_for_result_write(100);
        if (result_write_addr !== 16'd300 || result_write_mask[0] !== 1'b1) begin
            $display("[FAIL] bad result write addr=%0d mask=%h @t=%0t",
                     result_write_addr, result_write_mask, $time);
            $finish;
        end

        wait_for_done(100);

        print_result_matrix("Final result");
        check_result_matrix();

        $display("[PASS] TPU 4x4 matrix multiplication test");
        $finish;
    end

endmodule
