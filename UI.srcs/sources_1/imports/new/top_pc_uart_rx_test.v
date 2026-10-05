`timescale 1ns / 1ps

// ============================================================================
// PC UART RX 双向链路测试
//
// FPGA: XC7A200T
// CLK : W19 = 100 MHz
//
// PC -> CH340E -> FPGA
// UART_RXD = AA14
//
// FPGA -> CH340E -> PC
// UART_TXD = V14
//
// 115200 / 8N1
//
// Qt 发送:
// TEST\r\n
//
// FPGA 返回:
// FPGA RX: TEST\r\n
// ============================================================================

module top_pc_uart_rx_test
(
    input  wire sys_clk,

    // 保留这个端口只是为了兼容你当前 XDC
    // 本测试暂时不用 CH9350
    input  wire CH9350_RXD,

    // PC -> FPGA
    input  wire UART_RXD,

    // FPGA -> PC
    output wire UART_TXD,

    output reg  LED0,
    output reg  LED1
);


// ============================================================================
// 100 MHz / 115200 ≈ 868
// ============================================================================

localparam integer CLKS_PER_BIT = 868;


// ============================================================================
// UART RX
// ============================================================================

wire [7:0] pc_rx_data;
wire       pc_rx_valid;


pc_uart_rx_115200
#(
    .CLKS_PER_BIT(CLKS_PER_BIT)
)
u_pc_uart_rx
(
    .clk        (sys_clk),
    .rx         (UART_RXD),

    .data_out   (pc_rx_data),
    .data_valid (pc_rx_valid)
);


// ============================================================================
// UART TX
// ============================================================================

reg  [7:0] pc_tx_data;
reg        pc_tx_start;

wire       pc_tx_busy;
wire       pc_tx_done;


pc_uart_tx_115200
#(
    .CLKS_PER_BIT(CLKS_PER_BIT)
)
u_pc_uart_tx
(
    .clk      (sys_clk),

    .data_in  (pc_tx_data),
    .start    (pc_tx_start),

    .tx       (UART_TXD),

    .busy     (pc_tx_busy),
    .done     (pc_tx_done)
);


// ============================================================================
// 接收一行
//
// 最多保存 32 个字符。
// CR 忽略。
// LF 表示一行结束。
// ============================================================================

reg [7:0] line_buffer [0:31];

reg [5:0] rx_count;

reg [5:0] line_len;


// ============================================================================
// 发送状态
// ============================================================================

reg       send_active;

reg [6:0] send_index;

reg       tx_wait;


// ============================================================================
// 返回字符串:
//
// "FPGA RX: "
//
// 9 bytes
// ============================================================================

function [7:0] prefix_byte;

    input [3:0] index;

    begin

        case (index)

            4'd0:
                prefix_byte = "F";

            4'd1:
                prefix_byte = "P";

            4'd2:
                prefix_byte = "G";

            4'd3:
                prefix_byte = "A";

            4'd4:
                prefix_byte = " ";

            4'd5:
                prefix_byte = "R";

            4'd6:
                prefix_byte = "X";

            4'd7:
                prefix_byte = ":";

            4'd8:
                prefix_byte = " ";

            default:
                prefix_byte = 8'h20;

        endcase

    end

endfunction


// ============================================================================
// 主控制
// ============================================================================

integer i;

initial
begin

    LED0 = 1'b0;
    LED1 = 1'b0;

    rx_count = 0;
    line_len = 0;

    send_active = 1'b0;
    send_index  = 0;

    tx_wait = 1'b0;

    pc_tx_data  = 8'h00;
    pc_tx_start = 1'b0;

    for (i = 0; i < 32; i = i + 1)
    begin
        line_buffer[i] = 8'h00;
    end

end


always @(posedge sys_clk)
begin

    // start 永远只拉高一个周期
    pc_tx_start <= 1'b0;


    // ========================================================================
    // PC UART 接收
    // ========================================================================

    if (pc_rx_valid)
    begin

        // --------------------------------------------------------------------
        // CR
        // --------------------------------------------------------------------

        if (pc_rx_data == 8'h0D)
        begin

            // 忽略 CR

        end


        // --------------------------------------------------------------------
        // LF
        //
        // 一行接收完成
        // --------------------------------------------------------------------

        else if (pc_rx_data == 8'h0A)
        begin

            // 保存本行长度
            line_len <= rx_count;


            // 每收到一整行，LED0翻转一次
            // 这样肉眼非常容易判断 AA14 是否真的收到
            LED0 <= ~LED0;


            // 只有当前没有发送时才启动返回
            if (!send_active)
            begin

                send_active <= 1'b1;

                send_index <= 0;

                tx_wait <= 1'b0;

            end


            // 为下一行准备
            rx_count <= 0;

        end


        // --------------------------------------------------------------------
        // 普通字符
        // --------------------------------------------------------------------

        else
        begin

            if (rx_count < 32)
            begin

                line_buffer[rx_count] <= pc_rx_data;

                rx_count <= rx_count + 1'b1;

            end

        end

    end


    // ========================================================================
    // 当前一个 UART 字节真正发送完
    // ========================================================================

    if (pc_tx_done && tx_wait)
    begin

        tx_wait <= 1'b0;


        // --------------------------------------------------------------------
        // 最后一个字节已经发送完成
        //
        // 最终格式：
        //
        // prefix 9 bytes
        // +
        // line_len bytes
        // +
        // CR
        // +
        // LF
        //
        // 最后 index = line_len + 10
        // --------------------------------------------------------------------

        if (send_index == line_len + 7'd10)
        begin

            send_active <= 1'b0;

            send_index <= 0;


            // 每完成一次回传，LED1翻转
            LED1 <= ~LED1;

        end

        else
        begin

            send_index <= send_index + 1'b1;

        end

    end


    // ========================================================================
    // 启动下一个 TX 字节
    // ========================================================================

    if (
        send_active &&
        !tx_wait &&
        !pc_tx_busy
    )
    begin

        // --------------------------------------------------------------------
        // 0 ~ 8
        // "FPGA RX: "
        // --------------------------------------------------------------------

        if (send_index < 9)
        begin

            pc_tx_data <=
                prefix_byte(
                    send_index[3:0]
                );

        end


        // --------------------------------------------------------------------
        // 原始收到的内容
        // --------------------------------------------------------------------

        else if (
            send_index <
            (
                7'd9 +
                line_len
            )
        )
        begin

            pc_tx_data <=
                line_buffer[
                    send_index - 7'd9
                ];

        end


        // --------------------------------------------------------------------
        // CR
        // --------------------------------------------------------------------

        else if (
            send_index ==
            (
                7'd9 +
                line_len
            )
        )
        begin

            pc_tx_data <= 8'h0D;

        end


        // --------------------------------------------------------------------
        // LF
        // --------------------------------------------------------------------

        else
        begin

            pc_tx_data <= 8'h0A;

        end


        pc_tx_start <= 1'b1;

        tx_wait <= 1'b1;

    end

end


// 防止 unused warning 对功能没有影响
wire unused_ch9350;
assign unused_ch9350 = CH9350_RXD;


endmodule



// ============================================================================
// UART RX
//
// 115200 / 8N1
// ============================================================================

module pc_uart_rx_115200
#(
    parameter integer CLKS_PER_BIT = 868
)
(
    input  wire       clk,

    input  wire       rx,

    output reg [7:0]  data_out,

    output reg        data_valid
);


// ============================================================================
// 状态
// ============================================================================

localparam RX_IDLE  = 3'd0;
localparam RX_START = 3'd1;
localparam RX_DATA  = 3'd2;
localparam RX_STOP  = 3'd3;


reg [2:0] state;

integer clk_count;

reg [2:0] bit_index;

reg [7:0] rx_shift;


// ============================================================================
// RX 双触发同步
// ============================================================================

reg rx_meta;
reg rx_sync;


initial
begin

    state = RX_IDLE;

    clk_count = 0;

    bit_index = 0;

    rx_shift = 0;

    data_out = 0;

    data_valid = 0;

    rx_meta = 1'b1;

    rx_sync = 1'b1;

end


always @(posedge clk)
begin

    rx_meta <= rx;

    rx_sync <= rx_meta;


    data_valid <= 1'b0;


    case (state)


        // ====================================================================
        // 等待起始位
        // ====================================================================

        RX_IDLE:
        begin

            clk_count <= 0;

            bit_index <= 0;


            if (rx_sync == 1'b0)
            begin

                state <= RX_START;

            end

        end


        // ====================================================================
        // 起始位中点确认
        // ====================================================================

        RX_START:
        begin

            if (
                clk_count >=
                (
                    CLKS_PER_BIT / 2
                )
            )
            begin

                clk_count <= 0;


                if (rx_sync == 1'b0)
                begin

                    state <= RX_DATA;

                end

                else
                begin

                    state <= RX_IDLE;

                end

            end

            else
            begin

                clk_count <=
                    clk_count + 1;

            end

        end


        // ====================================================================
        // 8 数据位
        // ====================================================================

        RX_DATA:
        begin

            if (
                clk_count >=
                (
                    CLKS_PER_BIT - 1
                )
            )
            begin

                clk_count <= 0;


                rx_shift[bit_index]
                    <=
                    rx_sync;


                if (bit_index == 3'd7)
                begin

                    bit_index <= 0;

                    state <= RX_STOP;

                end

                else
                begin

                    bit_index <=
                        bit_index + 1'b1;

                end

            end

            else
            begin

                clk_count <=
                    clk_count + 1;

            end

        end


        // ====================================================================
        // 停止位
        // ====================================================================

        RX_STOP:
        begin

            if (
                clk_count >=
                (
                    CLKS_PER_BIT - 1
                )
            )
            begin

                clk_count <= 0;


                data_out <= rx_shift;

                data_valid <= 1'b1;


                state <= RX_IDLE;

            end

            else
            begin

                clk_count <=
                    clk_count + 1;

            end

        end


        default:
        begin

            state <= RX_IDLE;

        end

    endcase

end


endmodule



// ============================================================================
// UART TX
//
// 115200 / 8N1
// ============================================================================

module pc_uart_tx_115200
#(
    parameter integer CLKS_PER_BIT = 868
)
(
    input  wire      clk,

    input  wire [7:0] data_in,

    input  wire      start,

    output reg       tx,

    output reg       busy,

    output reg       done
);


// ============================================================================
// 状态
// ============================================================================

localparam TX_IDLE  = 3'd0;
localparam TX_START = 3'd1;
localparam TX_DATA  = 3'd2;
localparam TX_STOP  = 3'd3;


reg [2:0] state;

integer clk_count;

reg [2:0] bit_index;

reg [7:0] tx_shift;


initial
begin

    state = TX_IDLE;

    clk_count = 0;

    bit_index = 0;

    tx_shift = 0;

    tx = 1'b1;

    busy = 1'b0;

    done = 1'b0;

end


always @(posedge clk)
begin

    done <= 1'b0;


    case (state)


        // ====================================================================
        // IDLE
        // ====================================================================

        TX_IDLE:
        begin

            tx <= 1'b1;

            busy <= 1'b0;

            clk_count <= 0;

            bit_index <= 0;


            if (start)
            begin

                tx_shift <= data_in;

                busy <= 1'b1;

                state <= TX_START;

            end

        end


        // ====================================================================
        // START
        // ====================================================================

        TX_START:
        begin

            tx <= 1'b0;

            busy <= 1'b1;


            if (
                clk_count >=
                (
                    CLKS_PER_BIT - 1
                )
            )
            begin

                clk_count <= 0;

                state <= TX_DATA;

            end

            else
            begin

                clk_count <=
                    clk_count + 1;

            end

        end


        // ====================================================================
        // DATA
        // ====================================================================

        TX_DATA:
        begin

            tx <=
                tx_shift[bit_index];

            busy <= 1'b1;


            if (
                clk_count >=
                (
                    CLKS_PER_BIT - 1
                )
            )
            begin

                clk_count <= 0;


                if (bit_index == 3'd7)
                begin

                    bit_index <= 0;

                    state <= TX_STOP;

                end

                else
                begin

                    bit_index <=
                        bit_index + 1'b1;

                end

            end

            else
            begin

                clk_count <=
                    clk_count + 1;

            end

        end


        // ====================================================================
        // STOP
        // ====================================================================

        TX_STOP:
        begin

            tx <= 1'b1;

            busy <= 1'b1;


            if (
                clk_count >=
                (
                    CLKS_PER_BIT - 1
                )
            )
            begin

                clk_count <= 0;

                busy <= 1'b0;

                done <= 1'b1;

                state <= TX_IDLE;

            end

            else
            begin

                clk_count <=
                    clk_count + 1;

            end

        end


        default:
        begin

            state <= TX_IDLE;

            tx <= 1'b1;

            busy <= 1'b0;

        end

    endcase

end


endmodule