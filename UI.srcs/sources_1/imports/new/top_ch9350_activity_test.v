`timescale 1ns / 1ps

module top_ch9350_activity_test (
    input  wire sys_clk,
    input  wire CH9350_RXD,
    output reg  LED0 = 1'b0
);

    // ---------------------------------------------------------
    // CH9350_RXD 输入同步
    // ---------------------------------------------------------
    reg rx_d1   = 1'b1;
    reg rx_d2   = 1'b1;
    reg rx_last = 1'b1;

    // LED 保持约 0.3 秒
    // 100MHz × 0.3s = 30,000,000
    reg [24:0] led_cnt = 25'd0;

    always @(posedge sys_clk) begin

        rx_d1   <= CH9350_RXD;
        rx_d2   <= rx_d1;
        rx_last <= rx_d2;

        // 不管是什么协议、不管什么波特率，
        // 只要G15电平发生变化，就点亮LED0
        if (rx_d2 != rx_last) begin
            LED0    <= 1'b1;
            led_cnt <= 25'd30_000_000;
        end
        else if (led_cnt != 0) begin
            led_cnt <= led_cnt - 1'b1;
        end
        else begin
            LED0 <= 1'b0;
        end

    end

endmodule