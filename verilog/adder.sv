// Simple parameterized adder
module adder #(
    parameter WIDTH = 8
)(
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic [WIDTH:0]   sum   // one extra bit for carry out
);

    // Combinational add
    always_comb begin
        sum = a + b;
    end

endmodule
