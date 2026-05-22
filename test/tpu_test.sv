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
    DATA [T-1:0] weights_in;
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

    tpu #(
        .T(T)
    ) dut (
        .clock               (clock),
        .reset               (reset),
        .cmd_valid           (cmd_valid),
        .cmd_ready           (cmd_ready),
        .cmd                 (cmd),
        .activations_in      (activations_in),
        .weights_in          (weights_in),
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

    always_comb begin
        activations_in = '{default: '0};
        weights_in = '{default: '0};

        activations_in[0] = 32'd2;
        activations_in[1] = 32'd3;
        activations_in[2] = 32'd4;
        activations_in[3] = 32'd5;
        weights_in[0] = 32'd7;
        weights_in[1] = 32'd11;
        weights_in[2] = 32'd13;
        weights_in[3] = 32'd17;
    end

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        cmd_valid = 1'b0;
        fetch_result = 1'b0;
        cmd = '0;

        @(negedge clock);
        reset = 1'b0;

        cmd.activation_base_addr = 16'd100;
        cmd.weight_base_addr = 16'd200;
        cmd.output_base_addr = 16'd300;
        cmd.m_tiles = 8'd1;
        cmd.n_tiles = 8'd1;
        cmd.k_tiles = 8'd1;
        cmd_valid = 1'b1;

        @(posedge clock);
        #1;
        if (cmd_ready !== 1'b1) begin
            $display("[FAIL] TPU command queue was not ready @t=%0t", $time);
            $finish;
        end

        @(negedge clock);
        cmd_valid = 1'b0;

        wait (activation_read_req);
        #1;
        if (activation_read_req !== 1'b1 || activation_read_addr !== 16'd100) begin
            $display("[FAIL] activation request addr=%0d req=%0b @t=%0t",
                     activation_read_addr, activation_read_req, $time);
            $finish;
        end
        if (weight_read_req !== 1'b1 || weight_read_addr !== 16'd200) begin
            $display("[FAIL] weight request addr=%0d req=%0b @t=%0t",
                     weight_read_addr, weight_read_req, $time);
            $finish;
        end

        wait (result_write_req);
        #1;
        if (result_write_addr !== 16'd300 || result_write_mask[0] !== 1'b1) begin
            $display("[FAIL] bad result write addr=%0d mask=%h @t=%0t",
                     result_write_addr, result_write_mask, $time);
            $finish;
        end

        wait (done);

        $display("[PASS] TPU command queue/controller smoke test");
        $finish;
    end

endmodule
