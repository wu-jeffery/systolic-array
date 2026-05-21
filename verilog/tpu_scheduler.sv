`include "verilog/sys_defs.svh"

module tpu_scheduler #(
    parameter int T = `ARRAY_SIZE,
    parameter int K = `ARRAY_SIZE,
    parameter int MULT_PIPELINE_CYCLES = `MULT_PIPELINE_CYCLES,
    parameter int COUNT_WIDTH = 16
)(
    input logic clock,
    input logic reset,

    input logic start_compute,

    output logic busy,
    output logic done,
    output logic [(T*T)-1:0] accumulator_valid
);

    localparam int LAST_RESULT_CYCLE = K + ((T - 1) * 2) + MULT_PIPELINE_CYCLES;

    logic [COUNT_WIDTH-1:0] cycle_count;

    always_comb begin
        accumulator_valid = '0;

        for (int r = 0; r < T; r++) begin
            for (int c = 0; c < T; c++) begin
                if (busy && cycle_count == (K + r + c + MULT_PIPELINE_CYCLES)) begin
                    accumulator_valid[r*T + c] = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            busy <= 1'b0;
            done <= 1'b0;
            cycle_count <= '0;
        end else begin
            done <= 1'b0;

            if (start_compute && !busy) begin
                busy <= 1'b1;
                cycle_count <= '0;
            end else if (busy) begin
                if (cycle_count == LAST_RESULT_CYCLE) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    cycle_count <= '0;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end
        end
    end

endmodule
