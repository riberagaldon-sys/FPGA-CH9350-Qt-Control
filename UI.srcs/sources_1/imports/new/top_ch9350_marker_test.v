`timescale 1ns / 1ps

module top_ch9350_marker_test (
    input  wire sys_clk,
    input  wire CH9350_RXD,
    output wire UART_TXD,
    output reg  LED0 = 1'b0,
    output wire LED1
);

    parameter integer CLK_HZ      = 100_000_000;
    parameter integer CH9350_BAUD = 57600;
    parameter integer PC_BAUD     = 115200;


    // =========================================================
    // CH9350 UART RX
    // =========================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (CH9350_BAUD)
    ) u_rx (
        .clk   (sys_clk),
        .rx    (CH9350_RXD),
        .data  (rx_data),
        .valid (rx_valid)
    );


    // =========================================================
    // PC UART TX
    // =========================================================
    reg  [7:0] tx_data  = 8'h00;
    reg        tx_start = 1'b0;

    wire tx_busy;
    wire tx_done;

    assign LED1 = tx_busy;

    uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (PC_BAUD)
    ) u_tx (
        .clk   (sys_clk),
        .data  (tx_data),
        .start (tx_start),
        .tx    (UART_TXD),
        .busy  (tx_busy),
        .done  (tx_done)
    );


    // =========================================================
    // 每收到一个CH9350字节，记录一次事件
    // =========================================================
    reg event_pending = 1'b0;

    always @(posedge sys_clk) begin

        if (rx_valid)
            event_pending <= 1'b1;

        if (event_pending && !tx_busy && !tx_start)
            event_pending <= 1'b0;

    end


    // =========================================================
    // TX控制
    //
    // 每检测到一次CH9350有效字节：
    // 向PC发送 ASCII 'R' = 0x52
    // =========================================================
    reg [1:0] tx_state = 2'd0;

    always @(posedge sys_clk) begin

        tx_start <= 1'b0;

        case (tx_state)

            // 等待接收事件
            2'd0: begin

                if (event_pending && !tx_busy) begin

                    tx_data  <= 8'h52;   // ASCII 'R'
                    tx_start <= 1'b1;

                    tx_state <= 2'd1;

                end
            end


            // 等UART进入busy
            2'd1: begin

                if (tx_busy)
                    tx_state <= 2'd2;

            end


            // 等发送完成
            2'd2: begin

                if (tx_done)
                    tx_state <= 2'd0;

            end


            default:
                tx_state <= 2'd0;

        endcase

    end


    // =========================================================
    // LED0
    //
    // 只要CH9350 UART成功收到字节，
    // LED0保持约0.2秒
    // =========================================================
    reg [24:0] led_cnt = 25'd0;

    always @(posedge sys_clk) begin

        if (rx_valid) begin

            LED0    <= 1'b1;
            led_cnt <= 25'd20_000_000;

        end
        else if (led_cnt != 0) begin

            led_cnt <= led_cnt - 1'b1;

        end
        else begin

            LED0 <= 1'b0;

        end

    end

endmodule



// =============================================================
// UART RX
// 57600 8N1
// =============================================================
module uart_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 57600
)(
    input  wire       clk,
    input  wire       rx,

    output reg [7:0]  data  = 8'h00,
    output reg        valid = 1'b0
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam integer HALF_BIT     = CLKS_PER_BIT / 2;

    localparam [1:0]
        RX_IDLE  = 2'd0,
        RX_START = 2'd1,
        RX_DATA  = 2'd2,
        RX_STOP  = 2'd3;

    reg [1:0] state = RX_IDLE;

    reg rx_d1 = 1'b1;
    reg rx_d2 = 1'b1;

    reg [31:0] clk_cnt = 32'd0;
    reg [2:0]  bit_cnt = 3'd0;
    reg [7:0]  shift   = 8'h00;


    // 输入同步
    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end


    always @(posedge clk) begin

        valid <= 1'b0;

        case (state)

            RX_IDLE: begin

                clk_cnt <= 32'd0;
                bit_cnt <= 3'd0;

                if (rx_d2 == 1'b0)
                    state <= RX_START;

            end


            RX_START: begin

                if (clk_cnt == HALF_BIT - 1) begin

                    clk_cnt <= 32'd0;

                    if (rx_d2 == 1'b0)
                        state <= RX_DATA;
                    else
                        state <= RX_IDLE;

                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end

            end


            RX_DATA: begin

                if (clk_cnt == CLKS_PER_BIT - 1) begin

                    clk_cnt <= 32'd0;

                    shift[bit_cnt] <= rx_d2;

                    if (bit_cnt == 3'd7) begin

                        bit_cnt <= 3'd0;
                        state   <= RX_STOP;

                    end
                    else begin

                        bit_cnt <= bit_cnt + 1'b1;

                    end

                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end

            end


            RX_STOP: begin

                if (clk_cnt == CLKS_PER_BIT - 1) begin

                    clk_cnt <= 32'd0;

                    if (rx_d2 == 1'b1) begin

                        data  <= shift;
                        valid <= 1'b1;

                    end

                    state <= RX_IDLE;

                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end

            end


            default:
                state <= RX_IDLE;

        endcase

    end

endmodule



// =============================================================
// UART TX
// 115200 8N1
// =============================================================
module uart_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
)(
    input  wire       clk,
    input  wire [7:0] data,
    input  wire       start,

    output reg        tx   = 1'b1,
    output reg        busy = 1'b0,
    output reg        done = 1'b0
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    localparam [2:0]
        TX_IDLE  = 3'd0,
        TX_START = 3'd1,
        TX_DATA  = 3'd2,
        TX_STOP  = 3'd3;

    reg [2:0] state = TX_IDLE;

    reg [31:0] clk_cnt = 32'd0;
    reg [2:0]  bit_cnt = 3'd0;
    reg [7:0]  shift   = 8'h00;


    always @(posedge clk) begin

        done <= 1'b0;

        case (state)

            TX_IDLE: begin

                tx      <= 1'b1;
                busy    <= 1'b0;
                clk_cnt <= 32'd0;
                bit_cnt <= 3'd0;

                if (start) begin

                    shift <= data;

                    tx   <= 1'b0;
                    busy <= 1'b1;

                    state <= TX_START;

                end

            end


            TX_START: begin

                busy <= 1'b1;

                if (clk_cnt == CLKS_PER_BIT - 1) begin

                    clk_cnt <= 32'd0;

                    tx <= shift[0];

                    state <= TX_DATA;

                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end

            end


            TX_DATA: begin

                busy <= 1'b1;

                if (clk_cnt == CLKS_PER_BIT - 1) begin

                    clk_cnt <= 32'd0;

                    if (bit_cnt == 3'd7) begin

                        tx <= 1'b1;

                        state <= TX_STOP;

                    end
                    else begin

                        bit_cnt <= bit_cnt + 1'b1;

                        tx <= shift[bit_cnt + 1'b1];

                    end

                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end

            end


            TX_STOP: begin

                busy <= 1'b1;

                if (clk_cnt == CLKS_PER_BIT - 1) begin

                    clk_cnt <= 32'd0;

                    tx   <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;

                    state <= TX_IDLE;

                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end

            end


            default: begin

                state <= TX_IDLE;
                tx    <= 1'b1;
                busy  <= 1'b0;

            end

        endcase

    end

endmodule