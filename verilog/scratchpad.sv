`include "verilog/sys_defs.svh"

module scratchpad #(
    parameter int T = `ARRAY_SIZE,
    parameter int DEPTH = 1024,
    parameter int RESULT_WORDS = T*T
)(
    input logic clock,
    input logic reset,

    input logic host_write_req,
    input ADDR host_write_addr,
    input DATA host_write_data,
    output logic host_write_ready,

    input logic host_read_req,
    input ADDR host_read_addr,
    output logic host_read_valid,
    output DATA host_read_data,

    input logic activation_read_req,
    input ADDR activation_read_addr,
    output logic activation_read_valid,
    output DATA [T-1:0] activation_read_data,

    input logic weight_read_req,
    input ADDR weight_read_addr,
    output logic weight_read_valid,
    output DATA [T-1:0] weight_read_data,

    input logic result_write_req,
    input ADDR result_write_addr,
    input logic [RESULT_WORDS-1:0] result_write_mask,
    input DATA [RESULT_WORDS-1:0] result_write_data,
    output logic result_write_ready
);

    DATA mem [DEPTH-1:0];

    assign host_write_ready = 1'b1;
    assign result_write_ready = 1'b1;

    always_ff @(posedge clock) begin
        if (reset) begin
            host_read_valid <= 1'b0;
            host_read_data <= '0;
            activation_read_valid <= 1'b0;
            activation_read_data <= '0;
            weight_read_valid <= 1'b0;
            weight_read_data <= '0;
        end else begin
            host_read_valid <= host_read_req;
            activation_read_valid <= activation_read_req;
            weight_read_valid <= weight_read_req;

            if (host_write_req && host_write_ready && host_write_addr < DEPTH) begin
                mem[host_write_addr] <= host_write_data;
            end

            if (result_write_req && result_write_ready) begin
                for (int i = 0; i < RESULT_WORDS; i++) begin
                    if (result_write_mask[i] && result_write_addr + i < DEPTH) begin
                        mem[result_write_addr + i] <= result_write_data[i];
                    end
                end
            end

            if (host_read_req) begin
                if (host_read_addr < DEPTH) begin
                    host_read_data <= mem[host_read_addr];
                end else begin
                    host_read_data <= '0;
                end
            end

            if (activation_read_req) begin
                for (int i = 0; i < T; i++) begin
                    if (activation_read_addr + i < DEPTH) begin
                        activation_read_data[i] <= mem[activation_read_addr + i];
                    end else begin
                        activation_read_data[i] <= '0;
                    end
                end
            end

            if (weight_read_req) begin
                for (int i = 0; i < T; i++) begin
                    if (weight_read_addr + i < DEPTH) begin
                        weight_read_data[i] <= mem[weight_read_addr + i];
                    end else begin
                        weight_read_data[i] <= '0;
                    end
                end
            end
        end
    end

endmodule
