`timescale 1ns / 1ps

module top_ch9350_keyboard_parser (
    input  wire sys_clk,

    // CH9350L TXD -> FPGA
    input  wire CH9350_RXD,

    // FPGA -> CH340E -> PC
    output wire UART_TXD,

    // 完整键盘帧指示
    output reg  LED0 = 1'b0,

    // FPGA向PC发送时指示
    output wire LED1
);

    parameter integer CLK_HZ      = 100_000_000;
    parameter integer CH9350_BAUD = 115200;
    parameter integer PC_BAUD     = 115200;


    // ============================================================
    // CH9350 UART RX
    // ============================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    ch9350_keyboard_uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (CH9350_BAUD)
    ) u_ch9350_rx (
        .clk   (sys_clk),
        .rx    (CH9350_RXD),
        .data  (rx_data),
        .valid (rx_valid)
    );


    // ============================================================
    // 键盘帧：
    //
    // 57 AB 01
    // B0 B1 B2 B3 B4 B5 B6 B7
    //
    // B0 = Modifier
    // B1 = Reserved
    // B2~B7 = 6个按键码
    // ============================================================
    localparam [3:0]
        P_57 = 4'd0,
        P_AB = 4'd1,
        P_01 = 4'd2,
        P_B0 = 4'd3,
        P_B1 = 4'd4,
        P_B2 = 4'd5,
        P_B3 = 4'd6,
        P_B4 = 4'd7,
        P_B5 = 4'd8,
        P_B6 = 4'd9,
        P_B7 = 4'd10;

    reg [3:0] parser_state = P_57;

    reg [7:0] t0 = 8'h00;
    reg [7:0] t1 = 8'h00;
    reg [7:0] t2 = 8'h00;
    reg [7:0] t3 = 8'h00;
    reg [7:0] t4 = 8'h00;
    reg [7:0] t5 = 8'h00;
    reg [7:0] t6 = 8'h00;

    reg [63:0] keyboard_report = 64'h0;
    reg        keyboard_report_pulse = 1'b0;


    always @(posedge sys_clk) begin

        keyboard_report_pulse <= 1'b0;

        if (rx_valid) begin

            case (parser_state)

                P_57: begin
                    if (rx_data == 8'h57)
                        parser_state <= P_AB;
                end


                P_AB: begin

                    if (rx_data == 8'hAB)
                        parser_state <= P_01;

                    else if (rx_data == 8'h57)
                        parser_state <= P_AB;

                    else
                        parser_state <= P_57;

                end


                P_01: begin

                    if (rx_data == 8'h01)
                        parser_state <= P_B0;

                    else if (rx_data == 8'h57)
                        parser_state <= P_AB;

                    else
                        parser_state <= P_57;

                end


                P_B0: begin
                    t0 <= rx_data;
                    parser_state <= P_B1;
                end

                P_B1: begin
                    t1 <= rx_data;
                    parser_state <= P_B2;
                end

                P_B2: begin
                    t2 <= rx_data;
                    parser_state <= P_B3;
                end

                P_B3: begin
                    t3 <= rx_data;
                    parser_state <= P_B4;
                end

                P_B4: begin
                    t4 <= rx_data;
                    parser_state <= P_B5;
                end

                P_B5: begin
                    t5 <= rx_data;
                    parser_state <= P_B6;
                end

                P_B6: begin
                    t6 <= rx_data;
                    parser_state <= P_B7;
                end


                P_B7: begin

                    keyboard_report <= {
                        t0,
                        t1,
                        t2,
                        t3,
                        t4,
                        t5,
                        t6,
                        rx_data
                    };

                    keyboard_report_pulse <= 1'b1;

                    parser_state <= P_57;

                end


                default:
                    parser_state <= P_57;

            endcase

        end

    end


    // ============================================================
    // 8-entry Keyboard Report FIFO
    // 防止PC正在发送上一行时丢掉下一个键盘报告
    // ============================================================
    reg [63:0] report_fifo [0:7];

    reg [2:0] fifo_wr = 3'd0;
    reg [2:0] fifo_rd = 3'd0;
    reg [3:0] fifo_count = 4'd0;

    wire fifo_full  = (fifo_count == 8);
    wire fifo_empty = (fifo_count == 0);


    // ============================================================
    // PC UART
    // ============================================================
    reg  [7:0] pc_tx_data  = 8'h00;
    reg        pc_tx_start = 1'b0;

    wire pc_tx_busy;
    wire pc_tx_done;

    assign LED1 = pc_tx_busy;

    keyboard_pc_uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (PC_BAUD)
    ) u_pc_tx (
        .clk   (sys_clk),
        .data  (pc_tx_data),
        .start (pc_tx_start),
        .tx    (UART_TXD),
        .busy  (pc_tx_busy),
        .done  (pc_tx_done)
    );


    // ============================================================
    // 当前准备发送的键盘报告
    // ============================================================
    reg [63:0] send_report = 64'h0;


    // ============================================================
    // HEX ASCII
    // ============================================================
    function [7:0] hex_char;
        input [3:0] value;
        begin

            if (value <= 9)
                hex_char = "0" + value;
            else
                hex_char = "A" + (value - 10);

        end
    endfunction


    // 从64位报告中取第index个字节
    function [7:0] report_byte;
        input [2:0] index;
        begin

            case (index)

                3'd0: report_byte = send_report[63:56];
                3'd1: report_byte = send_report[55:48];
                3'd2: report_byte = send_report[47:40];
                3'd3: report_byte = send_report[39:32];
                3'd4: report_byte = send_report[31:24];
                3'd5: report_byte = send_report[23:16];
                3'd6: report_byte = send_report[15:8];
                3'd7: report_byte = send_report[7:0];

                default:
                    report_byte = 8'h00;

            endcase

        end
    endfunction


    // ============================================================
    // PC输出：
    //
    // K 00 00 2C 00 00 00 00 00\r\n
    //
    // 共27字节
    // ============================================================
    function [7:0] message_byte;
        input [5:0] index;

        reg [2:0] byte_index;
        reg [7:0] value;

        begin

            case (index)

                6'd0:
                    message_byte = "K";

                6'd1:
                    message_byte = " ";

                // Byte0
                6'd2: begin
                    value = report_byte(0);
                    message_byte = hex_char(value[7:4]);
                end

                6'd3: begin
                    value = report_byte(0);
                    message_byte = hex_char(value[3:0]);
                end

                6'd4:
                    message_byte = " ";


                // Byte1
                6'd5: begin
                    value = report_byte(1);
                    message_byte = hex_char(value[7:4]);
                end

                6'd6: begin
                    value = report_byte(1);
                    message_byte = hex_char(value[3:0]);
                end

                6'd7:
                    message_byte = " ";


                // Byte2
                6'd8: begin
                    value = report_byte(2);
                    message_byte = hex_char(value[7:4]);
                end

                6'd9: begin
                    value = report_byte(2);
                    message_byte = hex_char(value[3:0]);
                end

                6'd10:
                    message_byte = " ";


                // Byte3
                6'd11: begin
                    value = report_byte(3);
                    message_byte = hex_char(value[7:4]);
                end

                6'd12: begin
                    value = report_byte(3);
                    message_byte = hex_char(value[3:0]);
                end

                6'd13:
                    message_byte = " ";


                // Byte4
                6'd14: begin
                    value = report_byte(4);
                    message_byte = hex_char(value[7:4]);
                end

                6'd15: begin
                    value = report_byte(4);
                    message_byte = hex_char(value[3:0]);
                end

                6'd16:
                    message_byte = " ";


                // Byte5
                6'd17: begin
                    value = report_byte(5);
                    message_byte = hex_char(value[7:4]);
                end

                6'd18: begin
                    value = report_byte(5);
                    message_byte = hex_char(value[3:0]);
                end

                6'd19:
                    message_byte = " ";


                // Byte6
                6'd20: begin
                    value = report_byte(6);
                    message_byte = hex_char(value[7:4]);
                end

                6'd21: begin
                    value = report_byte(6);
                    message_byte = hex_char(value[3:0]);
                end

                6'd22:
                    message_byte = " ";


                // Byte7
                6'd23: begin
                    value = report_byte(7);
                    message_byte = hex_char(value[7:4]);
                end

                6'd24: begin
                    value = report_byte(7);
                    message_byte = hex_char(value[3:0]);
                end


                6'd25:
                    message_byte = 8'h0D;

                6'd26:
                    message_byte = 8'h0A;

                default:
                    message_byte = 8'h00;

            endcase

        end
    endfunction


    // ============================================================
    // TX状态机
    // ============================================================
    localparam [2:0]
        TX_IDLE      = 3'd0,
        TX_LOAD      = 3'd1,
        TX_WAIT_BUSY = 3'd2,
        TX_WAIT_DONE = 3'd3;

    reg [2:0] tx_state = TX_IDLE;
    reg [5:0] msg_index = 6'd0;

    wire pop_report =
        (tx_state == TX_IDLE) &&
        !fifo_empty &&
        !pc_tx_busy;

    wire push_report =
        keyboard_report_pulse &&
        (!fifo_full || pop_report);


    // ============================================================
    // FIFO
    // ============================================================
    always @(posedge sys_clk) begin

        if (push_report) begin
            report_fifo[fifo_wr] <= keyboard_report;
            fifo_wr <= fifo_wr + 1'b1;
        end

        if (pop_report) begin
            send_report <= report_fifo[fifo_rd];
            fifo_rd <= fifo_rd + 1'b1;
        end

        case ({push_report, pop_report})

            2'b10:
                fifo_count <= fifo_count + 1'b1;

            2'b01:
                fifo_count <= fifo_count - 1'b1;

            2'b11:
                fifo_count <= fifo_count;

            default:
                fifo_count <= fifo_count;

        endcase

    end


    // ============================================================
    // PC文本发送
    // ============================================================
    always @(posedge sys_clk) begin

        pc_tx_start <= 1'b0;

        case (tx_state)

            TX_IDLE: begin

                if (pop_report) begin
                    msg_index <= 6'd0;
                    tx_state  <= TX_LOAD;
                end

            end


            TX_LOAD: begin

                if (!pc_tx_busy) begin

                    pc_tx_data  <= message_byte(msg_index);
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

                    if (msg_index == 6'd26) begin
                        tx_state <= TX_IDLE;
                    end
                    else begin
                        msg_index <= msg_index + 1'b1;
                        tx_state <= TX_LOAD;
                    end

                end

            end


            default:
                tx_state <= TX_IDLE;

        endcase

    end


    // ============================================================
    // LED0
    // 完整键盘帧到达后亮0.2秒
    // ============================================================
    reg [24:0] led_cnt = 25'd0;

    always @(posedge sys_clk) begin

        if (keyboard_report_pulse) begin

            LED0 <= 1'b1;
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



// ============================================================================
// CH9350 Keyboard UART RX
// ============================================================================
module ch9350_keyboard_uart_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
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
                        state <= RX_STOP;
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
                        data <= shift;
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



// ============================================================================
// Keyboard PC UART TX
// ============================================================================
module keyboard_pc_uart_tx #(
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

                    tx <= 1'b1;
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