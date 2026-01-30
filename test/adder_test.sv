module adder_test;

    localparam WIDTH = 8;

    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic [WIDTH:0]   sum;

    // Instantiate DUT
    adder #(.WIDTH(WIDTH)) dut (
        .a(a),
        .b(b),
        .sum(sum)
    );

    // Task to check expected value
    task check(input logic [WIDTH-1:0] aa,
               input logic [WIDTH-1:0] bb);
        logic [WIDTH:0] expected;
        begin
            a = aa;
            b = bb;
            #1; // allow combinational logic to settle
            expected = aa + bb;
            if (sum !== expected) begin
                $display("@@@ Failed: a=%0d b=%0d sum=%0d expected=%0d",
                         aa, bb, sum, expected);
                $finish;
            end
        end
    endtask

    initial begin
        $display("=== Starting adder test ===");

        // Directed tests
        check(8'd0,   8'd0);
        check(8'd1,   8'd1);
        check(8'd15,  8'd1);
        check(8'd255, 8'd1);

        // Random tests
        repeat (50) begin
            check($urandom, $urandom);
        end

        $display("@@@ Passed");
        $finish;
    end

endmodule
