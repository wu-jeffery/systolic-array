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
    DATA [T-1:0] test_activations;
    DATA [T-1:0] test_weights;
    DATA [T-1:0] test_biases;
    DATA [(T*T)-1:0] output_matrix;

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

    function automatic DATA expected_postprocess(
        input DATA activation_value,
        input DATA weight_value,
        input DATA bias_value
    );
        logic signed [31:0] biased_value;
        begin
            biased_value = $signed(activation_value * weight_value) + $signed(bias_value);
            expected_postprocess = biased_value[31] ? '0 : biased_value;
        end
    endfunction

    task automatic host_read(input ADDR addr, output DATA data);
        @(negedge clock);
        host_read_req = 1'b1;
        host_read_addr = addr;
        @(negedge clock);
        host_read_req = 1'b0;
        #1;
        if (host_read_valid !== 1'b1) begin
            $display("[FAIL] scratchpad did not return data for address %0d @t=%0t",
                     addr, $time);
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

        test_activations[0] = 32'd2;
        test_activations[1] = 32'd3;
        test_activations[2] = 32'd4;
        test_activations[3] = 32'd5;
        test_weights[0] = 32'd7;
        test_weights[1] = 32'd11;
        test_weights[2] = 32'd13;
        test_weights[3] = 32'd17;
        test_biases[0] = 32'hfffffff0; // -16: exercises ReLU for the first row.
        test_biases[1] = 32'd1;
        test_biases[2] = 32'd2;
        test_biases[3] = 32'd3;
        output_matrix = '{default: '0};

        @(negedge clock);
        reset = 1'b0;

        $display("\n[TPU_SYSTEM] Writing activation array A to scratchpad base address 100:");
        $write("             A = [");
        for (int i = 0; i < T; i++) begin
            $write(" %0d", test_activations[i]);
            host_write(16'd100 + i, test_activations[i]);
        end
        $display(" ]  (addresses 100 through %0d)", 100 + T - 1);

        $display("[TPU_SYSTEM] Writing weight array B to scratchpad base address 200:");
        $write("             B = [");
        for (int i = 0; i < T; i++) begin
            $write(" %0d", test_weights[i]);
            host_write(16'd200 + i, test_weights[i]);
        end
        $display(" ]  (addresses 200 through %0d)", 200 + T - 1);

        for (int i = 0; i < T; i++) begin
            host_write(16'd250 + i, test_biases[i]);
        end

        cmd.activation_base_addr = 16'd100;
        cmd.weight_base_addr = 16'd200;
        cmd.bias_base_addr = 16'd250;
        cmd.output_base_addr = 16'd300;
        cmd.m_tiles = 8'd1;
        cmd.n_tiles = 8'd1;
        cmd.k_tiles = 8'd1;
        cmd.bias_enable = 1'b1;
        cmd.activation_type = ACT_RELU;

        $display("[TPU_SYSTEM] Starting A(column) x B(row) outer product");
        $display("             activation base = 100, weight base = 200, output base = 300");

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
        $display("[TPU_SYSTEM] TPU finished. Reading the %0dx%0d output from addresses 300 through %0d:",
                 T, T, 300 + (T*T) - 1);

        for (int i = 0; i < T*T; i++) begin
            host_read(16'd300 + i, output_matrix[i]);
        end

        for (int r = 0; r < T; r++) begin
            $write("             [");
            for (int c = 0; c < T; c++) begin
                $write(" %0d", output_matrix[r*T + c]);
                if (output_matrix[r*T + c] !== expected_postprocess(
                    test_activations[r], test_weights[c], test_biases[c])) begin
                    $display("\n[FAIL] output C[%0d][%0d] at address %0d: expected %0d, got %0d",
                             r, c, 300 + (r*T + c),
                             expected_postprocess(test_activations[r],
                                                  test_weights[c], test_biases[c]),
                             output_matrix[r*T + c]);
                    $finish;
                end
            end
            $display(" ]");
        end

        $display("[PASS] TPU system scratchpad input/output test");
        $finish;
    end

endmodule
