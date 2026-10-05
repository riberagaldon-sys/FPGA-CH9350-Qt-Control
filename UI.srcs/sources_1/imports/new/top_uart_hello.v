`timescale 1ns / 1ps

module top_ch9350_mouse_test (
    input  wire sys_clk,

    // CH9350L TXD -> FPGA
    input  wire CH9350_RXD,

    // FPGA -> CH340E -> PC
    output wire UART_TXD,

    // 检测到鼠标数据包时亮一下
    output reg  LED0 = 1'b0
);

    parameter integer CLK_HZ      = 100_000_000;
    parameter integer CH9350_BAUD = 57600;
    parameter integer PC_BAUD     = 115200;

    //============================================================
    // CH9350 UART RX
    //============================================================
    wire [7:0] ch_data;
    wire       ch_valid;

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (CH9350_BAUD)
    ) u_ch9350_rx (
        .clk   (sys_clk),
        .rx    (CH9350_RXD),
        .data  (ch_data),
        .valid (ch_valid)
    );


    //============================================================
    // CH9350 鼠标协议头检测
    //
    // 正常鼠标数据：
    // 57 AB 02 ...
    //============================================================
    reg [1:0] header_state = 2'd0;
    reg       mouse_pulse  = 1'b0;

    always @(posedge sys_clk) begin

        mouse_pulse <= 1'b0;

        if (ch_valid) begin

            case (header_state)

                2'd0: begin
                    if (ch_data == 8'h57)
                        header_state <= 2'd1;
                end

                2'd1: begin
                    if (ch_data == 8'hAB)
                        header_state <= 2'd2;
                    else if (ch_data == 8'h57)
                        header_state <= 2'd1;
                    else
                        header_state <= 2'd0;
                end

                2'd2: begin
                    if (ch_data == 8'h02) begin
                        mouse_pulse  <= 1'b1;
                        header_state <= 2'd0;
                    end
                    else if (ch_data == 8'h57) begin
                        header_state <= 2'd1;
                    end
                    else begin
                        header_state <= 2'd0;
                    end
                end

                default:
                    header_state <= 2'd0;

            endcase
        end
    end


    //============================================================
    // LED0
    // 检测到一个鼠标包，亮约0.25秒
    //============================================================
    reg [24:0] led_count = 25'd0;

    always @(posedge sys_clk) begin

        if (mouse_pulse) begin
            LED0      <= 1'b1;
            led_count <= 25_000_000;
        end
        else if (led_count != 0) begin
            led_count <= led_count - 1'b1;
        end
        else begin
            LED0 <= 1'b0;
        end

    end


    //============================================================
    // PC UART TX
    //============================================================
    reg  [7:0] pc_tx_data  = 8'h00;
    reg        pc_tx_start = 1'b0;

    wire       pc_tx_busy;
    wire       pc_tx_done;

    uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (PC_BAUD)
    ) u_pc_uart_tx (
        .clk   (sys_clk),
        .data  (pc_tx_data),
        .start (pc_tx_start),
        .tx    (UART_TXD),
        .busy  (pc_tx_busy),
        .done  (pc_tx_done)
    );


    //============================================================
    // 发送：
    //
    // MOUSE\r\n
    //============================================================
    function [7:0] message_byte;
        input [2:0] index;

        begin
            case (index)
                3'd0: message_byte = "M";
                3'd1: message_byte = "O";
                3'd2: message_byte = "U";
                3'd3: message_byte = "S";
                3'd4: message_byte = "E";
                3'd5: message_byte = 8'h0D;
                3'd6: message_byte = 8'h0A;
                default:
                      message_byte = 8'h00;
            endcase
        end
    endfunction


    localparam [1:0]
        TX_IDLE      = 2'd0,
        TX_SEND      = 2'd1,
        TX_WAIT_BUSY = 2'd2,
        TX_WAIT_DONE = 2'd3;

    reg [1:0] tx_state = TX_IDLE;
    reg [2:0] tx_index = 3'd0;

    always @(posedge sys_clk) begin

        pc_tx_start <= 1'b0;

        case (tx_state)

            TX_IDLE: begin

                if (mouse_pulse) begin
                    tx_index <= 3'd0;
                    tx_state <= TX_SEND;
                end

            end


            TX_SEND: begin

                if (!pc_tx_busy) begin

                    pc_tx_data  <= message_byte(tx_index);
                    pc_tx_start <= 1'b1;

                    tx_state <= TX_WAIT_BUSY;

                end

            end


            TX_WAIT_BUSY: begin

                if (pc_tx_busy)
                    tx_state <= TX_WAIT_DONE;

            end


            TX_WAIT_DONE: begin

                if (pc_tx_done) begin

                    if (tx_index == 3'd6) begin
                        tx_state <= TX_IDLE;
                    end
                    else begin
                        tx_index <= tx_index + 1'b1;
                        tx_state <= TX_SEND;
                    end

                end

            end

            default:
                tx_state <= TX_IDLE;

        endcase
    end

endmodule



//================================================================
// UART RX
//================================================================
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

    // 输入同步
    reg rx_d1 = 1'b1;
    reg rx_d2 = 1'b1;

    reg [31:0] clk_count = 32'd0;
    reg [2:0]  bit_index = 3'd0;
    reg [7:0]  data_reg  = 8'h00;

    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end


    always @(posedge clk) begin

        valid <= 1'b0;

        case (state)

            RX_IDLE: begin

                clk_count <= 32'd0;
                bit_index <= 3'd0;

                if (rx_d2 == 1'b0)
                    state <= RX_START;

            end


            RX_START: begin

                if (clk_count == HALF_BIT - 1) begin

                    clk_count <= 32'd0;

                    if (rx_d2 == 1'b0)
                        state <= RX_DATA;
                    else
                        state <= RX_IDLE;

                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end

            end


            RX_DATA: begin

                if (clk_count == CLKS_PER_BIT - 1) begin

                    clk_count <= 32'd0;

                    data_reg[bit_index] <= rx_d2;

                    if (bit_index == 3'd7) begin

                        bit_index <= 3'd0;
                        state     <= RX_STOP;

                    end
                    else begin

                        bit_index <= bit_index + 1'b1;

                    end

                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end

            end


            RX_STOP: begin

                if (clk_count == CLKS_PER_BIT - 1) begin

                    clk_count <= 32'd0;

                    data  <= data_reg;
                    valid <= 1'b1;

                    state <= RX_IDLE;

                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end

            end

            default:
                state <= RX_IDLE;

        endcase
    end

endmodule



//================================================================
// UART TX
//================================================================
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
        UART_IDLE  = 3'd0,
        UART_START = 3'd1,
        UART_DATA  = 3'd2,
        UART_STOP  = 3'd3;

    reg [2:0] state = UART_IDLE;

    reg [31:0] clk_count = 32'd0;
    reg [2:0]  bit_index = 3'd0;
    reg [7:0]  data_reg  = 8'h00;

    always @(posedge clk) begin

        case (state)

            UART_IDLE: begin

                tx        <= 1'b1;
                busy      <= 1'b0;
                done      <= 1'b0;
                clk_count <= 32'd0;
                bit_index <= 3'd0;

                if (start) begin

                    data_reg <= data;
                    tx       <= 1'b0;
                    busy     <= 1'b1;

                    state <= UART_START;

                end

            end


            UART_START: begin

                busy <= 1'b1;
                done <= 1'b0;

                if (clk_count == CLKS_PER_BIT - 1) begin

                    clk_count <= 32'd0;

                    tx <= data_reg[0];

                    state <= UART_DATA;

                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end

            end


            UART_DATA: begin

                busy <= 1'b1;
                done <= 1'b0;

                if (clk_count == CLKS_PER_BIT - 1) begin

                    clk_count <= 32'd0;

                    if (bit_index == 3'd7) begin

                        tx    <= 1'b1;
                        state <= UART_STOP;

                    end
                    else begin

                        bit_index <= bit_index + 1'b1;
                        tx        <= data_reg[bit_index + 1'b1];

                    end

                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end

            end


            UART_STOP: begin

                busy <= 1'b1;

                if (clk_count == CLKS_PER_BIT - 1) begin

                    clk_count <= 32'd0;

                    tx   <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;

                    state <= UART_IDLE;

                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end

            end

            default: begin

                tx    <= 1'b1;
                busy  <= 1'b0;
                done  <= 1'b0;
                state <= UART_IDLE;

            end

        endcase
    end

endmodule