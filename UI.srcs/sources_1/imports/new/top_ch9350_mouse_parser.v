`timescale 1ns / 1ps

module top_ch9350_mouse_parser (
    input  wire sys_clk,

    // CH9350L TXD -> FPGA
    input  wire CH9350_RXD,

    // FPGA -> CH340E -> PC
    output wire UART_TXD,

    // 成功解析到完整鼠标帧
    output reg  LED0 = 1'b0,

    // FPGA正在向PC发送
    output wire LED1
);

    parameter integer CLK_HZ      = 100_000_000;
    parameter integer CH9350_BAUD = 115200;
    parameter integer PC_BAUD     = 115200;

    // 50ms发送一次最新鼠标数据
    parameter integer REPORT_INTERVAL = 500_000;;


    // ============================================================
    // CH9350 UART RX
    // ============================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    ch9350_mouse_uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (CH9350_BAUD)
    ) u_ch9350_rx (
        .clk   (sys_clk),
        .rx    (CH9350_RXD),
        .data  (rx_data),
        .valid (rx_valid)
    );


    // ============================================================
    // CH9350 State-2 鼠标帧解析
    //
    // 57 AB 02 Button X Y Wheel
    // ============================================================
    localparam [2:0]
        P_WAIT_57 = 3'd0,
        P_WAIT_AB = 3'd1,
        P_WAIT_02 = 3'd2,
        P_BUTTON  = 3'd3,
        P_X       = 3'd4,
        P_Y       = 3'd5,
        P_WHEEL   = 3'd6;

    reg [2:0] parser_state = P_WAIT_57;

    reg [7:0] tmp_button = 8'h00;
    reg [7:0] tmp_x      = 8'h00;
    reg [7:0] tmp_y      = 8'h00;

    reg [7:0] mouse_button = 8'h00;
    reg [7:0] mouse_x      = 8'h00;
    reg [7:0] mouse_y      = 8'h00;
    reg [7:0] mouse_wheel  = 8'h00;

    reg mouse_packet_pulse = 1'b0;


    always @(posedge sys_clk) begin

        mouse_packet_pulse <= 1'b0;

        if (rx_valid) begin

            case (parser_state)

                P_WAIT_57: begin
                    if (rx_data == 8'h57)
                        parser_state <= P_WAIT_AB;
                end


                P_WAIT_AB: begin

                    if (rx_data == 8'hAB)
                        parser_state <= P_WAIT_02;

                    else if (rx_data == 8'h57)
                        parser_state <= P_WAIT_AB;

                    else
                        parser_state <= P_WAIT_57;

                end


                P_WAIT_02: begin

                    if (rx_data == 8'h02)
                        parser_state <= P_BUTTON;

                    else if (rx_data == 8'h57)
                        parser_state <= P_WAIT_AB;

                    else
                        parser_state <= P_WAIT_57;

                end


                P_BUTTON: begin

                    tmp_button   <= rx_data;
                    parser_state <= P_X;

                end


                P_X: begin

                    tmp_x        <= rx_data;
                    parser_state <= P_Y;

                end


                P_Y: begin

                    tmp_y        <= rx_data;
                    parser_state <= P_WHEEL;

                end


                P_WHEEL: begin

                    mouse_button <= tmp_button;
                    mouse_x      <= tmp_x;
                    mouse_y      <= tmp_y;
                    mouse_wheel  <= rx_data;

                    mouse_packet_pulse <= 1'b1;

                    parser_state <= P_WAIT_57;

                end


                default: begin
                    parser_state <= P_WAIT_57;
                end

            endcase

        end

    end


    // ============================================================
    // LED0
    // 每识别一个完整鼠标帧，保持约0.2秒
    // ============================================================
    reg [24:0] led_cnt = 25'd0;

    always @(posedge sys_clk) begin

        if (mouse_packet_pulse) begin

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


    // ============================================================
    // PC UART TX
    // ============================================================
    reg [7:0] pc_tx_data  = 8'h00;
    reg       pc_tx_start = 1'b0;

    wire pc_tx_busy;
    wire pc_tx_done;

    assign LED1 = pc_tx_busy;

    mouse_pc_uart_tx #(
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
    // 待发送的最新鼠标值
    // ============================================================
    reg pending = 1'b0;

    reg [7:0] send_button = 8'h00;
    reg [7:0] send_x      = 8'h00;
    reg [7:0] send_y      = 8'h00;
    reg [7:0] send_wheel  = 8'h00;


    // ============================================================
    // 转换为绝对值
    // ============================================================
    wire [7:0] x_mag;
    wire [7:0] y_mag;
    wire [7:0] w_mag;

    assign x_mag =
        send_x[7] ? ((~send_x) + 8'd1) : send_x;

    assign y_mag =
        send_y[7] ? ((~send_y) + 8'd1) : send_y;

    assign w_mag =
        send_wheel[7] ? ((~send_wheel) + 8'd1) : send_wheel;


    // ============================================================
    // HEX -> ASCII
    // ============================================================
    function [7:0] hex_char;
        input [3:0] value;
        begin

            if (value <= 4'd9)
                hex_char = "0" + value;
            else
                hex_char = "A" + (value - 4'd10);

        end
    endfunction


    // ============================================================
    // 十进制ASCII
    // ============================================================
    function [7:0] dec_hundred;
        input [7:0] value;
        begin
            dec_hundred = "0" + (value / 100);
        end
    endfunction

    function [7:0] dec_ten;
        input [7:0] value;
        begin
            dec_ten = "0" + ((value % 100) / 10);
        end
    endfunction

    function [7:0] dec_one;
        input [7:0] value;
        begin
            dec_one = "0" + (value % 10);
        end
    endfunction


    // ============================================================
    // 输出文本
    //
    // M B=00 X=+003 Y=-003 W=+000\r\n
    //
    // 总共29个字节
    // ============================================================
    function [7:0] message_byte;
        input [5:0] index;

        begin

            case (index)

                6'd0 : message_byte = "M";
                6'd1 : message_byte = " ";

                6'd2 : message_byte = "B";
                6'd3 : message_byte = "=";
                6'd4 : message_byte = hex_char(send_button[7:4]);
                6'd5 : message_byte = hex_char(send_button[3:0]);

                6'd6 : message_byte = " ";

                6'd7 : message_byte = "X";
                6'd8 : message_byte = "=";
                6'd9 : message_byte = send_x[7] ? "-" : "+";
                6'd10: message_byte = dec_hundred(x_mag);
                6'd11: message_byte = dec_ten(x_mag);
                6'd12: message_byte = dec_one(x_mag);

                6'd13: message_byte = " ";

                6'd14: message_byte = "Y";
                6'd15: message_byte = "=";
                6'd16: message_byte = send_y[7] ? "-" : "+";
                6'd17: message_byte = dec_hundred(y_mag);
                6'd18: message_byte = dec_ten(y_mag);
                6'd19: message_byte = dec_one(y_mag);

                6'd20: message_byte = " ";

                6'd21: message_byte = "W";
                6'd22: message_byte = "=";
                6'd23: message_byte = send_wheel[7] ? "-" : "+";
                6'd24: message_byte = dec_hundred(w_mag);
                6'd25: message_byte = dec_ten(w_mag);
                6'd26: message_byte = dec_one(w_mag);

                6'd27: message_byte = 8'h0D;
                6'd28: message_byte = 8'h0A;

                default:
                    message_byte = 8'h00;

            endcase

        end
    endfunction


    // ============================================================
    // PC发送状态机
    //
    // 注意：
    // cooldown_cnt 只允许在这个 always 块中赋值
    // 不会再出现 Multiple Driver
    // ============================================================
    localparam [2:0]
        TX_IDLE      = 3'd0,
        TX_LOAD      = 3'd1,
        TX_WAIT_BUSY = 3'd2,
        TX_WAIT_DONE = 3'd3;

    reg [2:0] tx_state = TX_IDLE;
    reg [5:0] msg_index = 6'd0;

    reg [22:0] cooldown_cnt = 23'd0;


    always @(posedge sys_clk) begin

        pc_tx_start <= 1'b0;


        // --------------------------------------------------------
        // 报告限速计数
        // cooldown_cnt只有这一个驱动源
        // --------------------------------------------------------
        if (cooldown_cnt != 0)
            cooldown_cnt <= cooldown_cnt - 1'b1;


        // --------------------------------------------------------
        // 新鼠标数据到达
        // --------------------------------------------------------
        if (mouse_packet_pulse)
            pending <= 1'b1;


        case (tx_state)

            // ====================================================
            // 等待需要发送的数据
            // ====================================================
            TX_IDLE: begin

                if (pending &&
                    (cooldown_cnt == 0) &&
                    !pc_tx_busy) begin

                    // 锁存最新鼠标状态
                    send_button <= mouse_button;
                    send_x      <= mouse_x;
                    send_y      <= mouse_y;
                    send_wheel  <= mouse_wheel;

                    pending   <= 1'b0;
                    msg_index <= 6'd0;

                    tx_state <= TX_LOAD;

                end

            end


            // ====================================================
            // 装载字符
            // ====================================================
            TX_LOAD: begin

                if (!pc_tx_busy) begin

                    pc_tx_data  <= message_byte(msg_index);
                    pc_tx_start <= 1'b1;

                    tx_state <= TX_WAIT_BUSY;

                end

            end


            // ====================================================
            // 等待UART开始发送
            // ====================================================
            TX_WAIT_BUSY: begin

                if (pc_tx_busy)
                    tx_state <= TX_WAIT_DONE;

            end


            // ====================================================
            // 等待当前字符发送完成
            // ====================================================
            TX_WAIT_DONE: begin

                if (pc_tx_done) begin

                    if (msg_index == 6'd28) begin

                        cooldown_cnt <= REPORT_INTERVAL - 1;

                        tx_state <= TX_IDLE;

                    end
                    else begin

                        msg_index <= msg_index + 1'b1;

                        tx_state <= TX_LOAD;

                    end

                end

            end


            default: begin

                tx_state <= TX_IDLE;

            end

        endcase

    end

endmodule



// ============================================================================
// CH9350 专用 UART RX
//
// 特意改名，避免与前面 raw_fifo / marker_test 中的 uart_rx 重名
// ============================================================================
module ch9350_mouse_uart_rx #(
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


    // 两级同步
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


            default: begin

                state <= RX_IDLE;

            end

        endcase

    end

endmodule



// ============================================================================
// 鼠标上位机专用 UART TX
//
// 特意改名，避免与前面测试代码中的 uart_tx 重名
// ============================================================================
module mouse_pc_uart_tx #(
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

        done <= 1'b0;

        case (state)

            UART_IDLE: begin

                tx        <= 1'b1;
                busy      <= 1'b0;
                clk_count <= 32'd0;
                bit_index <= 3'd0;

                if (start) begin

                    data_reg <= data;

                    tx   <= 1'b0;
                    busy <= 1'b1;

                    state <= UART_START;

                end

            end


            UART_START: begin

                busy <= 1'b1;

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

                if (clk_count == CLKS_PER_BIT - 1) begin

                    clk_count <= 32'd0;

                    if (bit_index == 3'd7) begin

                        tx <= 1'b1;

                        state <= UART_STOP;

                    end
                    else begin

                        bit_index <= bit_index + 1'b1;

                        tx <= data_reg[bit_index + 1'b1];

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

                state <= UART_IDLE;

                tx   <= 1'b1;
                busy <= 1'b0;

            end

        endcase

    end

endmodule