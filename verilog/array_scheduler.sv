`include "verilog/sys_defs.svh"

module array_scheduler #(
    parameter int T = `ARRAY_SIZE,
    parameter int MULT_PIPELINE_CYCLES = `MULT_PIPELINE_CYCLES,
    parameter int COUNT_WIDTH = 16
)(
    input logic clock,
    input logic reset,

    input logic start_compute,
    input logic [`TILE_COUNT_WIDTH-1:0] compute_length,

    output logic busy,
    output logic done,
    output logic [(T*T)-1:0] accumulator_valid
);

    logic [COUNT_WIDTH-1:0] cycle_count;
    logic [COUNT_WIDTH-1:0] active_compute_length;
    logic [COUNT_WIDTH-1:0] last_result_cycle;

    assign last_result_cycle = active_compute_length
                             + ((T - 1) * 2)
                             + MULT_PIPELINE_CYCLES;

    always_comb begin
        accumulator_valid = '0;

        if (busy && cycle_count == last_result_cycle) begin
            accumulator_valid = {T*T{1'b1}};
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            busy <= 1'b0;
            done <= 1'b0;
            cycle_count <= '0;
            active_compute_length <= '0;
        end else begin
            done <= 1'b0;

            if (start_compute && !busy) begin
                busy <= 1'b1;
                cycle_count <= '0;
                active_compute_length <= compute_length;
            end else if (busy) begin
                if (cycle_count == last_result_cycle) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    cycle_count <= '0;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end
        end
    end

    // Tile coordinates stay in tpu_controller. This scheduler times one
    // continuous stream of compute_length outer products and then waits for
    // the final wavefront to drain from the array.

endmodule
