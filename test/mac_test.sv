`include "verilog/sys_defs.svh"

module mac_test;

  logic clock;
  logic reset;
  logic clear_accumulator;

  DATA in_activation;
  DATA in_weight;
  DATA out_activation;
  DATA out_weight;
  DATA accumulator;

  // Instantiate DUT
  mac dut (
    .clock(clock),
    .reset(reset),
    .clear_accumulator(clear_accumulator),
    .in_activation(in_activation),
    .in_weight(in_weight),
    .out_activation(out_activation),
    .out_weight(out_weight),
    .accumulator(accumulator)
  );

  // -------------------------
  // Clock generator: 10ns period
  // -------------------------
  initial begin
    clock = 1'b0;
    forever #5 clock = ~clock;
  end

  // -------------------------
  // Scoreboard / expected model
  // -------------------------
  DATA exp_acc;
  DATA prev_in_act;
  DATA prev_in_wt;

  // Helper task: drive inputs aligned to clock edges
  task automatic drive_inputs(DATA act, DATA wt);
    // Drive on negedge so signals are stable before posedge sampling
    @(negedge clock);
    in_activation = act;
    in_weight     = wt;
  endtask

  // Helper task: check outputs right after posedge updates
  task automatic check_outputs(string tag);
    @(posedge clock);
    #1; // tiny delay to avoid race with nonblocking assignments

    // out_* are registered versions of inputs from *previous* cycle
    if (out_activation !== prev_in_act) begin
      $display("[FAIL] %s: out_activation=%0d expected=%0d @t=%0t",
               tag, out_activation, prev_in_act, $time);
      $fatal;
    end

    if (out_weight !== prev_in_wt) begin
      $display("[FAIL] %s: out_weight=%0d expected=%0d @t=%0t",
               tag, out_weight, prev_in_wt, $time);
      $fatal;
    end

    if (accumulator !== exp_acc) begin
      $display("[FAIL] %s: accumulator=%0d expected=%0d @t=%0t",
               tag, accumulator, exp_acc, $time);
      $fatal;
    end

    $display("[PASS] %s @t=%0t | out_act=%0d out_wt=%0d acc=%0d",
             tag, $time, out_activation, out_weight, accumulator);
  endtask

  // -------------------------
  // Main test sequence
  // -------------------------
  initial begin
    $dumpfile("mac_test.vcd");
    $dumpvars(0, mac_test);

    // Init
    reset = 1'b1;
    clear_accumulator = 1'b0;
    in_activation = '0;
    in_weight     = '0;

    exp_acc      = '0;
    prev_in_act  = '0;
    prev_in_wt   = '0;

    // Hold reset for 2 cycles
    repeat (2) begin
      // During reset, DUT forces outputs/acc to 0 on posedge.
      drive_inputs('0, '0);
      // Update "expected" for reset behavior
      exp_acc     = '0;
      prev_in_act = '0;
      prev_in_wt  = '0;
      check_outputs("reset_cycle");
    end

    // Deassert reset
    @(negedge clock);
    reset = 1'b0;

    // ---- Test vector 1 ----
    // On the next posedge:
    // accumulator = 0 + (2*3) = 6
    // out_activation/out_weight become (2,3)
    drive_inputs(DATA'(2), DATA'(3));

    // Expected model updates for that upcoming posedge
    exp_acc = exp_acc + (DATA'(2) * DATA'(3));
    // out_* reflect previous cycle's inputs; currently previous are 0,0
    prev_in_act = DATA'(2);
    prev_in_wt  = DATA'(3);
    check_outputs("vec1_update_acc_only_outs_prev");

    // After that posedge, the DUT's out_* now hold (2,3), so for next cycle:
    // ---- Test vector 2 ----
    // accumulator += (4*5) = 20 => 26 total
    drive_inputs(DATA'(4), DATA'(5));
    prev_in_act = DATA'(4);
    prev_in_wt  = DATA'(5);
    exp_acc     = exp_acc + (DATA'(4) * DATA'(5));
    check_outputs("vec2");

    // ---- Test vector 3 ----
    // accumulator += (-1*7) depending on signedness of DATA
    // If DATA is unsigned, this will wrap; that’s okay as long as expected matches.
    drive_inputs(DATA'(-1), DATA'(7));
    prev_in_act = DATA'(-1);
    prev_in_wt  = DATA'(7);
    exp_acc     = exp_acc + (DATA'(-1) * DATA'(7));
    check_outputs("vec3");

    // ---- Reset mid-stream ----
    @(negedge clock);
    reset = 1'b1;

    // Drive something nonzero; should still clear on posedge
    drive_inputs(DATA'(0), DATA'(0));
    exp_acc     = '0;
    prev_in_act = DATA'(0);
    prev_in_wt  = DATA'(0);
    check_outputs("mid_reset_clears");

    @(negedge clock);
    reset = 1'b0;
    clear_accumulator = 1'b1;
    drive_inputs(DATA'(9), DATA'(9));
    exp_acc = '0;
    prev_in_act = '0;
    prev_in_wt = '0;
    check_outputs("explicit_clear");

    // Drop clear and drive the next vector in the same cycle. Leaving the old
    // 9,9 inputs up for a cycle would correctly accumulate 81 before this check.
    @(negedge clock);
    clear_accumulator = 1'b0;
    in_activation = DATA'(1);
    in_weight = DATA'(8);

    // After explicit clear, everything starts from 0 again.
    prev_in_act = DATA'(1);
    prev_in_wt  = DATA'(8);
    exp_acc     = exp_acc + (DATA'(1) * DATA'(8));
    check_outputs("post_reset_vec");

    $display("@@@ Passed");
    $finish;
  end

endmodule
