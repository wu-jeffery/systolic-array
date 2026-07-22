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

        wait_for_activation_request(100);
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

        @(negedge clock);
        activations_valid = 1'b1;
        weights_valid = 1'b1;
        @(negedge clock);
        activations_valid = 1'b0;
        weights_valid = 1'b0;

        wait_for_result_write(100);
        if (result_write_addr !== 16'd300 || result_write_mask[0] !== 1'b1) begin
            $display("[FAIL] bad result write addr=%0d mask=%h @t=%0t",
                     result_write_addr, result_write_mask, $time);
            $finish;
        end

        wait_for_done(100);

        $display("[PASS] TPU command queue/controller smoke test");
        $finish;
    end

endmodule
