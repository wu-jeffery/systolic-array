`include "verilog/sys_defs.svh"

module tpu_command_queue #(
    parameter int DEPTH = `CMD_QUEUE_DEPTH,
    parameter int PTR_WIDTH = $clog2(DEPTH + 1)
)(
    input logic clock,
    input logic reset,

    input logic enqueue_valid,
    output logic enqueue_ready,
    input TPU_CMD enqueue_cmd,

    output logic dequeue_valid,
    input logic dequeue_ready,
    output TPU_CMD dequeue_cmd
);

    TPU_CMD queue [DEPTH-1:0];
    logic [PTR_WIDTH-1:0] head;
    logic [PTR_WIDTH-1:0] tail;
    logic [PTR_WIDTH-1:0] count;

    assign enqueue_ready = count < DEPTH;
    assign dequeue_valid = count != '0;
    assign dequeue_cmd = queue[head];

    always_ff @(posedge clock) begin
        if (reset) begin
            head <= '0;
            tail <= '0;
            count <= '0;
        end else begin
            if (enqueue_valid && enqueue_ready) begin
                queue[tail] <= enqueue_cmd;
                tail <= (tail == DEPTH - 1) ? '0 : tail + 1'b1;
            end

            if (dequeue_valid && dequeue_ready) begin
                head <= (head == DEPTH - 1) ? '0 : head + 1'b1;
            end

            case ({enqueue_valid && enqueue_ready, dequeue_valid && dequeue_ready})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
