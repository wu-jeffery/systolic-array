`include "verilog/sys_defs.svh"

module tpu_controller #(
    parameter int T = `ARRAY_SIZE
)(
    input logic clock,
    input logic reset,

    input logic cmd_valid,
    output logic cmd_ready,
    input TPU_CMD cmd,

    input logic array_busy,
    input logic array_done,
    input logic [(T*T)-1:0] accumulator_valid,

    output logic clear_accumulators,
    output logic load_activations,
    output logic load_weights,
    output logic start_compute,

    output logic activation_read_req,
    output ADDR activation_read_addr,
    input logic activation_read_valid,
    output logic weight_read_req,
    output ADDR weight_read_addr,
    input logic weight_read_valid,

    output logic result_write_req,
    output ADDR result_write_addr,
    output logic [(T*T)-1:0] result_write_mask,

    output logic busy,
    output logic done
);

    STATE state;
    TPU_CMD active_cmd;
    logic [`TILE_COUNT_WIDTH-1:0] current_m_tile;
    logic [`TILE_COUNT_WIDTH-1:0] current_n_tile;
    logic [`TILE_COUNT_WIDTH-1:0] current_k_tile;

    logic final_k_tile;
    ADDR tile_offset;
    ADDR activation_tile_index;
    ADDR weight_tile_index;

    assign final_k_tile = current_k_tile == (active_cmd.k_tiles - 1'b1);
    assign tile_offset = (current_m_tile * active_cmd.n_tiles) + current_n_tile;
    assign activation_tile_index = (current_m_tile * active_cmd.k_tiles) + current_k_tile;
    assign weight_tile_index = (current_k_tile * active_cmd.n_tiles) + current_n_tile;

    assign busy = state != STATE_IDLE;
    assign cmd_ready = state == STATE_IDLE;

    assign activation_read_addr = active_cmd.activation_base_addr + (activation_tile_index * T);
    assign weight_read_addr = active_cmd.weight_base_addr + (weight_tile_index * T);
    assign result_write_addr = active_cmd.output_base_addr + (tile_offset * T * T);
    assign result_write_mask = accumulator_valid;

    always_comb begin
        clear_accumulators = 1'b0;
        load_activations = 1'b0;
        load_weights = 1'b0;
        start_compute = 1'b0;
        activation_read_req = 1'b0;
        weight_read_req = 1'b0;
        result_write_req = 1'b0;

        case (state)
            STATE_CLEAR: begin
                clear_accumulators = 1'b1;
            end

            STATE_REQUEST: begin
                activation_read_req = 1'b1;
                weight_read_req = 1'b1;
            end

            STATE_WAIT_READ: begin
                load_activations = 1'b1;
                load_weights = 1'b1;
            end

            STATE_START: begin
                start_compute = !array_busy;
            end

            STATE_RUN: begin
                result_write_req = final_k_tile && (|accumulator_valid);
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            state <= STATE_IDLE;
            active_cmd <= '0;
            current_m_tile <= '0;
            current_n_tile <= '0;
            current_k_tile <= '0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (cmd_valid) begin
                        active_cmd <= cmd;
                        current_m_tile <= '0;
                        current_n_tile <= '0;
                        current_k_tile <= '0;
                        state <= STATE_CLEAR;
                    end
                end

                STATE_CLEAR: begin
                    state <= STATE_REQUEST;
                end

                STATE_REQUEST: begin
                    state <= STATE_WAIT_READ;
                end

                STATE_WAIT_READ: begin
                    if (activation_read_valid && weight_read_valid) begin
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (!array_busy) begin
                        state <= STATE_RUN;
                    end
                end

                STATE_RUN: begin
                    if (array_done) begin
                        state <= STATE_ADVANCE;
                    end
                end

                STATE_ADVANCE: begin
                    if (current_k_tile + 1'b1 < active_cmd.k_tiles) begin
                        current_k_tile <= current_k_tile + 1'b1;
                        state <= STATE_REQUEST;
                    end else if (current_n_tile + 1'b1 < active_cmd.n_tiles) begin
                        current_k_tile <= '0;
                        current_n_tile <= current_n_tile + 1'b1;
                        state <= STATE_CLEAR;
                    end else if (current_m_tile + 1'b1 < active_cmd.m_tiles) begin
                        current_k_tile <= '0;
                        current_n_tile <= '0;
                        current_m_tile <= current_m_tile + 1'b1;
                        state <= STATE_CLEAR;
                    end else begin
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
