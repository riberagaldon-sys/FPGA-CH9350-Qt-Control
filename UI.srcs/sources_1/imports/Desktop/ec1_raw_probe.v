`timescale 1ns / 1ps

// Standalone EC1 input probe. Set this module as the Vivado top for this test.
// Uses the same EC1 pins as the working Game(7) constraints: AB18/AA19/AB20.
// The UART prints synchronized input levels and hexadecimal edge counts.
module ec1_raw_probe #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD = 115200
) (
    input  wire sys_clk,
    input  wire EC_A,
    input  wire EC_B,
    input  wire EC_KEY,
    output reg  UART_TXD = 1'b1,
    output wire LED0,
    output wire LED1
);
    localparam integer BIT_CYCLES = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer REPORT_CYCLES = CLK_HZ / 5;
    localparam integer FRAME_BYTES = 30;

    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync = 2'b11;
    (* ASYNC_REG = "TRUE" *) reg [1:0] b_sync = 2'b11;
    (* ASYNC_REG = "TRUE" *) reg [1:0] k_sync = 2'b11;
    reg a_old = 1'b1;
    reg b_old = 1'b1;
    reg [15:0] a_edges = 16'd0;
    reg [15:0] b_edges = 16'd0;

    // Odd/even number of transitions remains visible on the LEDs at rest.
    // LED polarity on a particular board may be reversed; a change is key.
    assign LED0 = a_edges[0];
    assign LED1 = b_edges[0];

    function [7:0] hex_digit;
        input [3:0] n;
        begin
            hex_digit = (n < 10) ? (8'h30 + {4'b0,n})
                                 : (8'h41 + {4'b0,n} - 8'd10);
        end
    endfunction

    function [7:0] binary_digit;
        input n;
        begin binary_digit = n ? "1" : "0"; end
    endfunction

    reg [31:0] report_timer = 32'd0;
    reg [FRAME_BYTES*8-1:0] frame = {FRAME_BYTES{8'h20}};
    reg sending = 1'b0;
    reg [5:0] byte_index = 6'd0;
    reg tx_active = 1'b0;
    reg [9:0] tx_bits = 10'h3ff;
    reg [3:0] bit_index = 4'd0;
    reg [31:0] bit_timer = 32'd0;

    always @(posedge sys_clk) begin
        a_sync <= {a_sync[0], EC_A};
        b_sync <= {b_sync[0], EC_B};
        k_sync <= {k_sync[0], EC_KEY};
        a_old <= a_sync[1];
        b_old <= b_sync[1];
        if (a_sync[1] != a_old) a_edges <= a_edges + 16'd1;
        if (b_sync[1] != b_old) b_edges <= b_edges + 16'd1;

        if (report_timer == REPORT_CYCLES - 1) begin
            report_timer <= 32'd0;
            if (!sending && !tx_active) begin
                // Exactly 30 bytes: EC A=1 B=1 K=1 a=0000 b=0000\r\n
                frame <= {"EC A=", binary_digit(a_sync[1]),
                          " B=", binary_digit(b_sync[1]),
                          " K=", binary_digit(k_sync[1]),
                          " a=", hex_digit(a_edges[15:12]),
                                  hex_digit(a_edges[11:8]),
                                  hex_digit(a_edges[7:4]),
                                  hex_digit(a_edges[3:0]),
                          " b=", hex_digit(b_edges[15:12]),
                                  hex_digit(b_edges[11:8]),
                                  hex_digit(b_edges[7:4]),
                                  hex_digit(b_edges[3:0]), 8'h0d, 8'h0a};
                byte_index <= 6'd0;
                sending <= 1'b1;
            end
        end else begin
            report_timer <= report_timer + 32'd1;
        end

        if (tx_active) begin
            if (bit_timer == BIT_CYCLES - 1) begin
                bit_timer <= 32'd0;
                if (bit_index == 4'd9) begin
                    tx_active <= 1'b0;
                    UART_TXD <= 1'b1;
                end else begin
                    bit_index <= bit_index + 4'd1;
                    UART_TXD <= tx_bits[bit_index + 4'd1];
                end
            end else begin
                bit_timer <= bit_timer + 32'd1;
            end
        end else if (sending) begin
            // FPGA sends least significant data bit first (115200, 8N1).
            tx_bits <= {1'b1, frame[(FRAME_BYTES-1-byte_index)*8 +: 8], 1'b0};
            UART_TXD <= 1'b0;
            bit_timer <= 32'd0;
            bit_index <= 4'd0;
            tx_active <= 1'b1;
            if (byte_index == FRAME_BYTES-1)
                sending <= 1'b0;
            else
                byte_index <= byte_index + 6'd1;
        end
    end
endmodule
