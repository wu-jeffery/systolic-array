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
    output logic clear_accumulators,
    output logic load_activations,
    output logic load_weights,
    output logic start_compute,
    output logic [`TILE_COUNT_WIDTH-1:0] compute_length,

    output logic activation_read_req,
    output ADDR activation_read_addr,
    input logic activation_read_valid,
    output logic weight_read_req,
    output ADDR weight_read_addr,
    input logic weight_read_valid,

    output logic bias_read_req,
    output ADDR bias_read_addr,
    input logic bias_read_valid,

    output logic postprocess_start,
    input logic postprocess_done,
    output logic bias_enable,
    output ACTIVATION_TYPE activation_type,

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
    logic [`TILE_COUNT_WIDTH-1:0] issued_k_steps;
    logic [`TILE_COUNT_WIDTH-1:0] received_k_steps;
    ADDR tile_offset;
    ADDR activation_tile_index;
    ADDR weight_tile_index;

    assign tile_offset = (current_m_tile * active_cmd.n_tiles) + current_n_tile;
    assign activation_tile_index = (current_m_tile * active_cmd.k_tiles) + issued_k_steps;
    assign weight_tile_index = (issued_k_steps * active_cmd.n_tiles) + current_n_tile;
    assign compute_length = active_cmd.k_tiles;

    assign busy = state != STATE_IDLE;
    assign cmd_ready = state == STATE_IDLE;

    assign activation_read_addr = active_cmd.activation_base_addr + (activation_tile_index * T);
    assign weight_read_addr = active_cmd.weight_base_addr + (weight_tile_index * T);
    assign bias_read_addr = active_cmd.bias_base_addr + (current_n_tile * T);
    assign result_write_addr = active_cmd.output_base_addr + (tile_offset * T * T);
    assign result_write_mask = (state == STATE_WRITE) ? {T*T{1'b1}} : '0;
    assign bias_enable = active_cmd.bias_enable;
    assign activation_type = active_cmd.activation_type;

    always_comb begin
        clear_accumulators = 1'b0;
        load_activations = 1'b0;
        load_weights = 1'b0;
        start_compute = 1'b0;
        activation_read_req = 1'b0;
        weight_read_req = 1'b0;
        bias_read_req = 1'b0;
        postprocess_start = 1'b0;
        result_write_req = 1'b0;

        case (state)
            STATE_CLEAR: begin
                clear_accumulators = 1'b1;
            end

            STATE_REQUEST: begin
                activation_read_req = issued_k_steps < active_cmd.k_tiles;
                weight_read_req = issued_k_steps < active_cmd.k_tiles;
                load_activations = activation_read_valid && weight_read_valid;
                load_weights = activation_read_valid && weight_read_valid;
                start_compute = load_activations && (received_k_steps == '0);
            end


            STATE_BIAS_REQUEST: begin
                bias_read_req = 1'b1;
            end

            STATE_POSTPROCESS_START: begin
                postprocess_start = 1'b1;
            end

            STATE_WRITE: begin
                result_write_req = 1'b1;
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
            issued_k_steps <= '0;
            received_k_steps <= '0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (cmd_valid) begin
                        active_cmd <= cmd;
                        current_m_tile <= '0;
                        current_n_tile <= '0;
                        issued_k_steps <= '0;
                        received_k_steps <= '0;
                        state <= STATE_CLEAR;
                    end
                end

                STATE_CLEAR: begin
                    state <= STATE_REQUEST;
                end

                STATE_REQUEST: begin
                    if (activation_read_req && weight_read_req) begin
                        issued_k_steps <= issued_k_steps + 1'b1;
                    end

                    if (activation_read_valid && weight_read_valid) begin
                        received_k_steps <= received_k_steps + 1'b1;
                        if (received_k_steps + 1'b1 == active_cmd.k_tiles) begin
                            state <= STATE_RUN;
                        end
                    end
                end

                STATE_RUN: begin
                    if (array_done) begin
                        if (active_cmd.bias_enable) begin
                            state <= STATE_BIAS_REQUEST;
                        end else begin
                            state <= STATE_POSTPROCESS_START;
                        end
                    end
                end


                STATE_BIAS_REQUEST: begin
                    state <= STATE_BIAS_WAIT;
                end

                STATE_BIAS_WAIT: begin
                    if (bias_read_valid) begin
                        state <= STATE_POSTPROCESS_START;
                    end
                end

                STATE_POSTPROCESS_START: begin
                    state <= STATE_POSTPROCESS_WAIT;
                end

                STATE_POSTPROCESS_WAIT: begin
                    if (postprocess_done) begin
                        state <= STATE_WRITE;
                    end
                end

                STATE_WRITE: begin
                    state <= STATE_ADVANCE;
                end

                STATE_ADVANCE: begin
                    if (current_n_tile + 1'b1 < active_cmd.n_tiles) begin
                        issued_k_steps <= '0;
                        received_k_steps <= '0;
                        current_n_tile <= current_n_tile + 1'b1;
                        state <= STATE_CLEAR;
                    end else if (current_m_tile + 1'b1 < active_cmd.m_tiles) begin
                        issued_k_steps <= '0;
                        received_k_steps <= '0;
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
