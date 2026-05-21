`include "verilog/sys_defs.svh"

module tpu_test ();
    localparam int T = `ARRAY_SIZE;

    logic clock;
    logic reset;
    logic load_activations;
    logic load_weights;
    logic start_compute;
    logic fetch_result;

    DATA [T-1:0] activations_in;
    DATA [T-1:0] weights_in;
    logic busy;
    logic done;
    logic accumulators_valid;
    logic [(T*T)-1:0] accumulator_valid;
    DATA [(T*T)-1:0] accumulators;
    DATA expected_top_left;

    tpu #(
        .T(T)
    ) dut (
        .clock             (clock),
        .reset             (reset),
        .load_activations  (load_activations),
        .load_weights      (load_weights),
        .activations_in    (activations_in),
        .weights_in        (weights_in),
        .start_compute     (start_compute),
        .fetch_result      (fetch_result),
        .busy              (busy),
        .done              (done),
        .accumulators_valid(accumulators_valid),
        .accumulator_valid (accumulator_valid),
        .accumulators      (accumulators)
    );

    always #5 clock = ~clock;

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        load_activations = 1'b0;
        load_weights = 1'b0;
        start_compute = 1'b0;
        fetch_result = 1'b0;
        activations_in = '{default: '0};
        weights_in = '{default: '0};

        @(negedge clock);
        reset = 1'b0;

        activations_in[0] = 32'd2;
        activations_in[1] = 32'd3;
        activations_in[2] = 32'd4;
        activations_in[3] = 32'd5;
        weights_in[0] = 32'd7;
        weights_in[1] = 32'd11;
        weights_in[2] = 32'd13;
        weights_in[3] = 32'd17;
        load_activations = 1'b1;
        load_weights = 1'b1;

        @(negedge clock);
        load_activations = 1'b0;
        load_weights = 1'b0;
        start_compute = 1'b1;

        @(negedge clock);
        start_compute = 1'b0;
        expected_top_left = activations_in[0] * weights_in[0];
        if (accumulators[0] !== expected_top_left) begin
            $display("[FAIL] top-left accumulator=%0d expected=%0d @t=%0t",
                     accumulators[0], expected_top_left, $time);
            $finish;
        end

        fetch_result = 1'b1;
        #1;
        if (accumulators_valid !== 1'b1) begin
            $display("[FAIL] accumulators_valid did not follow fetch_result @t=%0t", $time);
            $finish;
        end
        fetch_result = 1'b0;

        repeat (4) @(posedge clock);
        #1;
        if (accumulator_valid[0] !== 1'b1 || accumulators_valid !== 1'b1) begin
            $display("[FAIL] scheduler did not mark accumulator 0 valid @t=%0t", $time);
            $finish;
        end

        wait (done);

        $display("[PASS] tpu buffer-to-array smoke test");
        $finish;
    end

endmodule
