// EC1_FIXED_VERSION
// EC_KEY is separated from EC_A/EC_B.
// EC_A/EC_B use quadrature direction decoding.
// Generated for EC11 hardware verification.

`timescale 1ns / 1ps

// ============================================================================
// CH9350L USB Keyboard + Mouse -> FPGA -> PC
//
// CH9350L:
//   Keyboard : 57 AB 01 + 8 bytes
//   Mouse    : 57 AB 02 + Button X Y Wheel
//
// PC ASCII output:
//
//   Keyboard:
//   K 00 00 0E 00 00 00 00 00\r\n
//
//   Mouse:
//   M B=01 X=+003 Y=-002 W=+000\r\n
//
// Board:
//   sys_clk      W19   100MHz
//   CH9350_RXD   G15
//   UART_RXD     AA14   PC -> FPGA
//   UART_TXD     V14    FPGA -> PC
//   LED0         J16
//   LED1         E22
// ============================================================================

module top_ch9350_keyboard_mouse (
    input  wire sys_clk,

    // CH9350L TXD -> FPGA
    input  wire CH9350_RXD,
    input  wire UART_RXD,

    // Physical FPGA_EC1. EC_B and DC motor direction-B share FPGA pin AA19.
    // One top-level inout port is used for that physical pin; do not create a
    // second DC_MOTORB top-level port or constrain two ports to AA19.
    input  wire EC_A,
    // AA19 shared pin:
    //   EC1_HW_MODE=1 -> high-impedance input for physical EC_B
    //   EC1_HW_MODE=0 -> DC motor direction-B output
    inout  wire EC_B,
    input  wire EC_KEY,

    // FPGA -> CH340E -> PC
    output wire UART_TXD,

    // Stepper motor drive -> baseboard U15
    output wire I_SETP_MOTOR_BA,
    output wire I_SETP_MOTOR_BB,
    output wire I_SETP_MOTOR_BC,
    output wire I_SETP_MOTOR_BD,
    // DC motor
    output wire DC_MOTORA,
    // Optical speed-feedback input.  Baseboard U16 detects the rotor mark;
    // U14 shapes it and also drives the nearby green indicator LED.
    input  wire DC_MOTOR_SPEED,

    output wire LED0,
    output wire LED1
);

    parameter integer CLK_HZ      = 100_000_000;
    parameter integer CH9350_BAUD = 115200;
    parameter integer PC_BAUD     = 115200;

    // 1: physical EC1 mode, BSW_CTRL1 4/5/6 = ON/ON/ON.
    //    AA19 is high impedance and is sampled as EC_B.
    // 0: DC motor mode, BSW_CTRL1 4/5/6 = ON/OFF/ON.
    //    AA19 is driven as DC_MOTORB.
    // Default to DC motor mode.  Use BSW_CTRL1 4/5/6 = ON/OFF/ON.
    // Change this parameter back to 1 only when testing physical FPGA_EC1,
    // together with BSW_CTRL1 4/5/6 = ON/ON/ON.
    parameter integer EC1_HW_MODE     = 1;
    parameter integer EC1_DIR_INVERT  = 0;
    // 1 selects the board-compatible, mechanically debounced Gray decoder.
    // It reports one direction only after the shaft returns to detent state 11.
    parameter integer EC1_COMPAT_MODE = 1;
    parameter integer EC1_LOCKOUT_MS  = 20;


    // ========================================================================
    // CH9350 UART RX
    // ========================================================================

    wire [7:0] rx_data;
    wire       rx_valid;


    ch9350_combo_uart_rx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (CH9350_BAUD)
    ) u_ch9350_rx (
        .clk   (sys_clk),
        .rx    (CH9350_RXD),
        .data  (rx_data),
        .valid (rx_valid)
    );


    // ========================================================================
    // Event 绫诲瀷
    // ========================================================================

    localparam [1:0] EV_MOUSE    = 2'd0;
    localparam [1:0] EV_KEYBOARD = 2'd1;
    localparam [1:0] EV_EC1      = 2'd2;
    localparam [1:0] EV_DC       = 2'd3;

    // DC telemetry is produced by the optical-sensor block near the motor
    // drive logic and is inserted into the common UART event FIFO.
    reg [63:0] dc_report_payload = 64'd0;
    reg        dc_report_pending = 1'b1;
    wire       dc_report_consumed;


    // ========================================================================
    // CH9350鍗忚瑙ｆ瀽鐘舵��
    //
    // 57 AB 01 + 8 byte keyboard
    // 57 AB 02 + 4 byte mouse
    // ========================================================================

    localparam [3:0]
        P_WAIT_57 = 4'd0,
        P_WAIT_AB = 4'd1,
        P_TYPE    = 4'd2,

        P_M_B     = 4'd3,
        P_M_X     = 4'd4,
        P_M_Y     = 4'd5,
        P_M_W     = 4'd6,

        P_K0      = 4'd7,
        P_K1      = 4'd8,
        P_K2      = 4'd9,
        P_K3      = 4'd10,
        P_K4      = 4'd11,
        P_K5      = 4'd12,
        P_K6      = 4'd13,
        P_K7      = 4'd14;


    reg [3:0] parser_state = P_WAIT_57;


    // 涓存椂缂撳瓨
    reg [7:0] tmp0 = 8'h00;
    reg [7:0] tmp1 = 8'h00;
    reg [7:0] tmp2 = 8'h00;
    reg [7:0] tmp3 = 8'h00;
    reg [7:0] tmp4 = 8'h00;
    reg [7:0] tmp5 = 8'h00;
    reg [7:0] tmp6 = 8'h00;


    // 瀹屾暣浜嬩欢
    reg [1:0]  event_type    = EV_MOUSE;
    reg [63:0] event_payload = 64'h0;
    reg        event_pulse   = 1'b0;


    // ========================================================================
    // CH9350甯цВ鏋�
    // ========================================================================

    always @(posedge sys_clk) begin

        event_pulse <= 1'b0;


        if (rx_valid) begin

            case (parser_state)

                // ------------------------------------------------------------
                // Header 57
                // ------------------------------------------------------------

                P_WAIT_57: begin

                    if (rx_data == 8'h57)
                        parser_state <= P_WAIT_AB;

                end


                // ------------------------------------------------------------
                // Header AB
                // ------------------------------------------------------------

                P_WAIT_AB: begin

                    if (rx_data == 8'hAB) begin

                        parser_state <= P_TYPE;

                    end
                    else if (rx_data == 8'h57) begin

                        parser_state <= P_WAIT_AB;

                    end
                    else begin

                        parser_state <= P_WAIT_57;

                    end

                end


                // ------------------------------------------------------------
                // Type
                //
                // 01 = keyboard
                // 02 = relative mouse
                // ------------------------------------------------------------

                P_TYPE: begin

                    if (rx_data == 8'h01) begin

                        parser_state <= P_K0;

                    end
                    else if (rx_data == 8'h02) begin

                        parser_state <= P_M_B;

                    end
                    else if (rx_data == 8'h57) begin

                        parser_state <= P_WAIT_AB;

                    end
                    else begin

                        parser_state <= P_WAIT_57;

                    end

                end


                // ============================================================
                // Mouse
                //
                // Button
                // X
                // Y
                // Wheel
                // ============================================================

                P_M_B: begin

                    tmp0 <= rx_data;
                    parser_state <= P_M_X;

                end


                P_M_X: begin

                    tmp1 <= rx_data;
                    parser_state <= P_M_Y;

                end


                P_M_Y: begin

                    tmp2 <= rx_data;
                    parser_state <= P_M_W;

                end


                P_M_W: begin

                    // payload:
                    //
                    // [31:24] Button
                    // [23:16] X
                    // [15:8]  Y
                    // [7:0]   Wheel

                    event_payload <= {
                        32'h00000000,
                        tmp0,
                        tmp1,
                        tmp2,
                        rx_data
                    };

                    event_type  <= EV_MOUSE;
                    event_pulse <= 1'b1;

                    parser_state <= P_WAIT_57;

                end


                // ============================================================
                // Keyboard
                //
                // Modifier
                // Reserved
                // Key1
                // Key2
                // Key3
                // Key4
                // Key5
                // Key6
                // ============================================================

                P_K0: begin

                    tmp0 <= rx_data;
                    parser_state <= P_K1;

                end


                P_K1: begin

                    tmp1 <= rx_data;
                    parser_state <= P_K2;

                end


                P_K2: begin

                    tmp2 <= rx_data;
                    parser_state <= P_K3;

                end


                P_K3: begin

                    tmp3 <= rx_data;
                    parser_state <= P_K4;

                end


                P_K4: begin

                    tmp4 <= rx_data;
                    parser_state <= P_K5;

                end


                P_K5: begin

                    tmp5 <= rx_data;
                    parser_state <= P_K6;

                end


                P_K6: begin

                    tmp6 <= rx_data;
                    parser_state <= P_K7;

                end


                P_K7: begin

                    event_payload <= {
                        tmp0,
                        tmp1,
                        tmp2,
                        tmp3,
                        tmp4,
                        tmp5,
                        tmp6,
                        rx_data
                    };

                    event_type  <= EV_KEYBOARD;
                    event_pulse <= 1'b1;

                    parser_state <= P_WAIT_57;

                end


                default: begin

                    parser_state <= P_WAIT_57;

                end

            endcase

        end

    end





    // ========================================================================
    // Physical FPGA_EC1 -> event report
    //
    // The verified Chapter-4 decoder accepts one complete quadrature cycle as
    // one detent. The active-low push key is debounced for 20 ms. A press
    // clears the signed count to zero, matching the earlier hardware test.
    //
    // UART line generated for Qt:
    //   E C=+00001 D=+ K=0\r\n
    //   E C=-00001 D=- K=0\r\n
    //   E C=+00000 D=0 K=1\r\n
    // ========================================================================

    reg [20:0] ec1_por_count = 21'd0;
    wire       ec1_rst_n = &ec1_por_count;

    always @(posedge sys_clk) begin
        if (!ec1_rst_n)
            ec1_por_count <= ec1_por_count + 1'b1;
    end

    wire ec1_raw_cw_pulse;
    wire ec1_raw_ccw_pulse;
    wire ec1_cw_pulse;
    wire ec1_ccw_pulse;
    wire ec1_rotate_pulse;
    wire ec1_key_level;
    wire ec1_key_press;
    wire ec1_key_release;

    // EC11 鍙岀浉姝ｄ氦瑙ｇ爜
    // A/B 涓よ矾鍧囨潵鑷墿鐞� EC1 鏃嬭浆瑙︾偣
    ch9350_ec11_quad_decoder #(
        .CLK_HZ      (CLK_HZ),
        .LOCKOUT_MS  (EC1_LOCKOUT_MS)
    ) u_physical_ec1_quad (
        .clk          (sys_clk),
        .rst_n        (ec1_rst_n && !ec1_key_level),
        .ec_a         (EC_A),
        .ec_b         (EC_B),
        .cw_pulse     (ec1_raw_cw_pulse),
        .ccw_pulse    (ec1_raw_ccw_pulse)
    );

    // Optional direction inversion.  Leave EC1_DIR_INVERT=0 unless the
    // physical clockwise/counter-clockwise labels are reversed.
    assign ec1_cw_pulse  =
        (EC1_DIR_INVERT != 0) ? ec1_raw_ccw_pulse : ec1_raw_cw_pulse;
    assign ec1_ccw_pulse =
        (EC1_DIR_INVERT != 0) ? ec1_raw_cw_pulse  : ec1_raw_ccw_pulse;

    assign ec1_rotate_pulse = ec1_cw_pulse | ec1_ccw_pulse;

    ch9350_debounce_event #(
        .CLK_HZ      (CLK_HZ),
        .DEBOUNCE_MS (20),
        .ACTIVE_LOW  (1)
    ) u_physical_ec1_key (
        .clk           (sys_clk),
        .rst_n         (ec1_rst_n),
        .key_in        (EC_KEY),
        .key_level     (ec1_key_level),
        .press_pulse   (ec1_key_press),
        .release_pulse (ec1_key_release)
    );

    localparam [1:0]
        EC_DIR_STOP = 2'd0,
        EC_DIR_CW   = 2'd1,
        EC_DIR_CCW  = 2'd2;

    reg signed [15:0] ec1_hw_count = 16'sd0;
    reg [1:0]         ec1_last_dir = EC_DIR_STOP;
    reg [63:0]        ec1_report_payload = 64'd0;
    reg               ec1_report_pending = 1'b1;

    // Asserted by the shared event FIFO when the saved EC1 report is accepted.
    wire ec1_report_consumed;

    wire ec1_hw_event =
        (EC1_HW_MODE != 0) &&
        (ec1_cw_pulse || ec1_ccw_pulse ||
         ec1_key_press || ec1_key_release);

    always @(posedge sys_clk) begin
        if (!ec1_rst_n) begin
            ec1_hw_count       <= 16'sd0;
            ec1_last_dir       <= EC_DIR_STOP;
            ec1_report_payload <= {
                16'sd0, EC_DIR_STOP, 1'b0, 45'd0
            };
            ec1_report_pending <= (EC1_HW_MODE != 0);
        end
        else begin
            if (ec1_report_consumed)
                ec1_report_pending <= 1'b0;

            if ((EC1_HW_MODE != 0) && ec1_key_press) begin
                ec1_report_payload <= {
                    ec1_hw_count,
                    ec1_last_dir,
                    1'b1,
                    45'd0
                };
                ec1_report_pending <= 1'b1;
            end
            else if ((EC1_HW_MODE != 0) && ec1_key_release) begin
                ec1_report_payload <= {
                    ec1_hw_count,
                    ec1_last_dir,
                    1'b0,
                    45'd0
                };
                ec1_report_pending <= 1'b1;
            end
            else if ((EC1_HW_MODE != 0) && ec1_cw_pulse) begin
                ec1_hw_count <= ec1_hw_count + 16'sd1;
                ec1_last_dir <= EC_DIR_CW;
                ec1_report_payload <= {
                    (ec1_hw_count + 16'sd1),
                    EC_DIR_CW,
                    ec1_key_level,
                    45'd0
                };
                ec1_report_pending <= 1'b1;
            end
            else if ((EC1_HW_MODE != 0) && ec1_ccw_pulse) begin
                ec1_hw_count <= ec1_hw_count - 16'sd1;
                ec1_last_dir <= EC_DIR_CCW;
                ec1_report_payload <= {
                    (ec1_hw_count - 16'sd1),
                    EC_DIR_CCW,
                    ec1_key_level,
                    45'd0
                };
                ec1_report_pending <= 1'b1;
            end
        end
    end


    // ========================================================================
    // PC -> FPGA UART RX
    //
    // Qt / COM9 -> CH340E -> AA14 -> UART_RXD
    // 115200 / 8N1
    // ========================================================================

    wire [7:0] pc_rx_data;
    wire       pc_rx_valid;


    ch9350_combo_uart_rx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (PC_BAUD)
    ) u_pc_rx (
        .clk   (sys_clk),
        .rx    (UART_RXD),
        .data  (pc_rx_data),
        .valid (pc_rx_valid)
    );


    // ========================================================================
    // PC 鍛戒护琛岀紦瀛�
    //
    // 鏀寔鍛戒护:
    //
    // TEST
    //
    // STEP START
    // STEP STOP
    // STEP CW
    // STEP CCW
    // STEP SPEED 1..10
    //
    // DC START
    // DC STOP
    // DC FWD
    // DC REV
    // DC PWM 0..100
    //
    // EC1 PRESS
    // EC1 RELEASE
    // EC1 VALUE 0..100
    //
    // 姣忔潯鍛戒护浠� \r\n 缁撴潫銆�
    // FPGA 杩斿洖:
    //
    // ACK <鍘熷懡浠�>\r\n
    // ERR <鍘熷懡浠�>\r\n
    // ========================================================================

    reg [255:0] pc_cmd_line = 256'h0;
    reg [5:0]   pc_cmd_len  = 6'd0;


    // 姣忔帴鏀跺畬涓�琛岋紝浜х敓涓�涓搷搴斾簨浠�
    reg         cmd_response_pulse = 1'b0;
    reg         cmd_response_ok    = 1'b0;
    reg [5:0]   cmd_response_len   = 6'd0;
    reg [255:0] cmd_response_line  = 256'h0;


    // ========================================================================
    // Qt 鍛戒护瀵瑰簲鐨� FPGA 鐘舵�佸瘎瀛樺櫒
    //
    // 杩欎竴鐗堝厛瀹屾垚"鎺ユ敹 + 瑙ｆ瀽 + ACK + 鐘舵�佷繚瀛�"銆�
    // 涓嬩竴姝ュ啀鎶婅繖浜涘瘎瀛樺櫒鎺ュ埌瀹為檯姝ヨ繘鐢垫満 / 鐩存祦鐢垫満纭欢杈撳嚭銆�
    // ========================================================================

    localparam [1:0]
        DIR_STOP = 2'd0,
        DIR_FWD  = 2'd1,
        DIR_REV  = 2'd2;


    reg       step_running   = 1'b0;
    reg [1:0] step_direction = DIR_STOP;
    reg [3:0] step_speed     = 4'd5;


    reg       dc_running   = 1'b0;
    reg [1:0] dc_direction = DIR_STOP;
    reg [6:0] dc_pwm       = 7'd50;


    reg       ec1_pressed = 1'b0;
    reg [6:0] ec1_value   = 7'd50;


    // ========================================================================
    // 鍙栧懡浠や腑鐨勭 index 涓瓧绗�
    // ========================================================================

    function [7:0] cmd_char;

        input [5:0] index;

        begin

            cmd_char =
                pc_cmd_line[
                    (index * 8) +: 8
                ];

        end

    endfunction


    function is_digit;

        input [7:0] value;

        begin

            is_digit =
                (value >= "0") &&
                (value <= "9");

        end

    endfunction


    function [7:0] digit_value;

        input [7:0] value;

        begin

            digit_value =
                value - "0";

        end

    endfunction


    // ========================================================================
    // 鍥哄畾鍛戒护姣旇緝
    // ========================================================================

    wire cmd_test =
        (pc_cmd_len == 6'd4) &&
        (cmd_char(0) == "T") &&
        (cmd_char(1) == "E") &&
        (cmd_char(2) == "S") &&
        (cmd_char(3) == "T");


    wire cmd_step_start =
        (pc_cmd_len == 6'd10) &&
        (cmd_char(0) == "S") &&
        (cmd_char(1) == "T") &&
        (cmd_char(2) == "E") &&
        (cmd_char(3) == "P") &&
        (cmd_char(4) == " ") &&
        (cmd_char(5) == "S") &&
        (cmd_char(6) == "T") &&
        (cmd_char(7) == "A") &&
        (cmd_char(8) == "R") &&
        (cmd_char(9) == "T");


    wire cmd_step_stop =
        (pc_cmd_len == 6'd9) &&
        (cmd_char(0) == "S") &&
        (cmd_char(1) == "T") &&
        (cmd_char(2) == "E") &&
        (cmd_char(3) == "P") &&
        (cmd_char(4) == " ") &&
        (cmd_char(5) == "S") &&
        (cmd_char(6) == "T") &&
        (cmd_char(7) == "O") &&
        (cmd_char(8) == "P");


    wire cmd_step_cw =
        (pc_cmd_len == 6'd7) &&
        (cmd_char(0) == "S") &&
        (cmd_char(1) == "T") &&
        (cmd_char(2) == "E") &&
        (cmd_char(3) == "P") &&
        (cmd_char(4) == " ") &&
        (cmd_char(5) == "C") &&
        (cmd_char(6) == "W");


    wire cmd_step_ccw =
        (pc_cmd_len == 6'd8) &&
        (cmd_char(0) == "S") &&
        (cmd_char(1) == "T") &&
        (cmd_char(2) == "E") &&
        (cmd_char(3) == "P") &&
        (cmd_char(4) == " ") &&
        (cmd_char(5) == "C") &&
        (cmd_char(6) == "C") &&
        (cmd_char(7) == "W");


    wire step_speed_prefix =
        ((pc_cmd_len == 6'd12) ||
         (pc_cmd_len == 6'd13)) &&
        (cmd_char(0)  == "S") &&
        (cmd_char(1)  == "T") &&
        (cmd_char(2)  == "E") &&
        (cmd_char(3)  == "P") &&
        (cmd_char(4)  == " ") &&
        (cmd_char(5)  == "S") &&
        (cmd_char(6)  == "P") &&
        (cmd_char(7)  == "E") &&
        (cmd_char(8)  == "E") &&
        (cmd_char(9)  == "D") &&
        (cmd_char(10) == " ");


    wire [7:0] parsed_step_speed =
        (pc_cmd_len == 6'd12)
            ? digit_value(cmd_char(11))
            : (
                digit_value(cmd_char(11)) * 8'd10 +
                digit_value(cmd_char(12))
              );


    wire step_speed_digits_ok =
        (pc_cmd_len == 6'd12)
            ? is_digit(cmd_char(11))
            : (
                is_digit(cmd_char(11)) &&
                is_digit(cmd_char(12))
              );


    wire cmd_step_speed =
        step_speed_prefix &&
        step_speed_digits_ok &&
        (parsed_step_speed >= 8'd1) &&
        (parsed_step_speed <= 8'd10);


    wire cmd_dc_start =
        (pc_cmd_len == 6'd8) &&
        (cmd_char(0) == "D") &&
        (cmd_char(1) == "C") &&
        (cmd_char(2) == " ") &&
        (cmd_char(3) == "S") &&
        (cmd_char(4) == "T") &&
        (cmd_char(5) == "A") &&
        (cmd_char(6) == "R") &&
        (cmd_char(7) == "T");


    wire cmd_dc_stop =
        (pc_cmd_len == 6'd7) &&
        (cmd_char(0) == "D") &&
        (cmd_char(1) == "C") &&
        (cmd_char(2) == " ") &&
        (cmd_char(3) == "S") &&
        (cmd_char(4) == "T") &&
        (cmd_char(5) == "O") &&
        (cmd_char(6) == "P");


    wire cmd_dc_fwd =
        (pc_cmd_len == 6'd6) &&
        (cmd_char(0) == "D") &&
        (cmd_char(1) == "C") &&
        (cmd_char(2) == " ") &&
        (cmd_char(3) == "F") &&
        (cmd_char(4) == "W") &&
        (cmd_char(5) == "D");


    wire cmd_dc_rev =
        (pc_cmd_len == 6'd6) &&
        (cmd_char(0) == "D") &&
        (cmd_char(1) == "C") &&
        (cmd_char(2) == " ") &&
        (cmd_char(3) == "R") &&
        (cmd_char(4) == "E") &&
        (cmd_char(5) == "V");


    wire dc_pwm_prefix =
        (pc_cmd_len >= 6'd8) &&
        (pc_cmd_len <= 6'd10) &&
        (cmd_char(0) == "D") &&
        (cmd_char(1) == "C") &&
        (cmd_char(2) == " ") &&
        (cmd_char(3) == "P") &&
        (cmd_char(4) == "W") &&
        (cmd_char(5) == "M") &&
        (cmd_char(6) == " ");


    wire dc_pwm_digits_ok =
        (pc_cmd_len == 6'd8)
            ? is_digit(cmd_char(7))
            : (
                (pc_cmd_len == 6'd9)
                    ? (
                        is_digit(cmd_char(7)) &&
                        is_digit(cmd_char(8))
                      )
                    : (
                        is_digit(cmd_char(7)) &&
                        is_digit(cmd_char(8)) &&
                        is_digit(cmd_char(9))
                      )
              );


    wire [9:0] parsed_dc_pwm =
        (pc_cmd_len == 6'd8)
            ? {2'b00, digit_value(cmd_char(7))}
            : (
                (pc_cmd_len == 6'd9)
                    ? (
                        {2'b00, digit_value(cmd_char(7))} * 10'd10 +
                        {2'b00, digit_value(cmd_char(8))}
                      )
                    : (
                        {2'b00, digit_value(cmd_char(7))} * 10'd100 +
                        {2'b00, digit_value(cmd_char(8))} * 10'd10 +
                        {2'b00, digit_value(cmd_char(9))}
                      )
              );


    wire cmd_dc_pwm =
        dc_pwm_prefix &&
        dc_pwm_digits_ok &&
        (parsed_dc_pwm <= 10'd100);


    wire cmd_ec1_press =
        (pc_cmd_len == 6'd9) &&
        (cmd_char(0) == "E") &&
        (cmd_char(1) == "C") &&
        (cmd_char(2) == "1") &&
        (cmd_char(3) == " ") &&
        (cmd_char(4) == "P") &&
        (cmd_char(5) == "R") &&
        (cmd_char(6) == "E") &&
        (cmd_char(7) == "S") &&
        (cmd_char(8) == "S");


    wire cmd_ec1_release =
        (pc_cmd_len == 6'd11) &&
        (cmd_char(0)  == "E") &&
        (cmd_char(1)  == "C") &&
        (cmd_char(2)  == "1") &&
        (cmd_char(3)  == " ") &&
        (cmd_char(4)  == "R") &&
        (cmd_char(5)  == "E") &&
        (cmd_char(6)  == "L") &&
        (cmd_char(7)  == "E") &&
        (cmd_char(8)  == "A") &&
        (cmd_char(9)  == "S") &&
        (cmd_char(10) == "E");


    wire ec1_value_prefix =
        (pc_cmd_len >= 6'd11) &&
        (pc_cmd_len <= 6'd13) &&
        (cmd_char(0) == "E") &&
        (cmd_char(1) == "C") &&
        (cmd_char(2) == "1") &&
        (cmd_char(3) == " ") &&
        (cmd_char(4) == "V") &&
        (cmd_char(5) == "A") &&
        (cmd_char(6) == "L") &&
        (cmd_char(7) == "U") &&
        (cmd_char(8) == "E") &&
        (cmd_char(9) == " ");


    wire ec1_value_digits_ok =
        (pc_cmd_len == 6'd11)
            ? is_digit(cmd_char(10))
            : (
                (pc_cmd_len == 6'd12)
                    ? (
                        is_digit(cmd_char(10)) &&
                        is_digit(cmd_char(11))
                      )
                    : (
                        is_digit(cmd_char(10)) &&
                        is_digit(cmd_char(11)) &&
                        is_digit(cmd_char(12))
                      )
              );


    wire [9:0] parsed_ec1_value =
        (pc_cmd_len == 6'd11)
            ? {2'b00, digit_value(cmd_char(10))}
            : (
                (pc_cmd_len == 6'd12)
                    ? (
                        {2'b00, digit_value(cmd_char(10))} * 10'd10 +
                        {2'b00, digit_value(cmd_char(11))}
                      )
                    : (
                        {2'b00, digit_value(cmd_char(10))} * 10'd100 +
                        {2'b00, digit_value(cmd_char(11))} * 10'd10 +
                        {2'b00, digit_value(cmd_char(12))}
                      )
              );


    wire cmd_ec1_value =
        ec1_value_prefix &&
        ec1_value_digits_ok &&
        (parsed_ec1_value <= 10'd100);


    wire cmd_recognized =
        cmd_test          ||
        cmd_step_start    ||
        cmd_step_stop     ||
        cmd_step_cw       ||
        cmd_step_ccw      ||
        cmd_step_speed    ||
        cmd_dc_start      ||
        cmd_dc_stop       ||
        cmd_dc_fwd        ||
        cmd_dc_rev        ||
        cmd_dc_pwm        ||
        cmd_ec1_press     ||
        cmd_ec1_release   ||
        cmd_ec1_value;


    // ========================================================================
    // PC 鍛戒护鎺ユ敹 / 瑙ｆ瀽
    // ========================================================================

    always @(posedge sys_clk) begin

        cmd_response_pulse <= 1'b0;


        if (pc_rx_valid) begin

            // ------------------------------------------------------------
            // CR: 蹇界暐
            // ------------------------------------------------------------

            if (pc_rx_data == 8'h0D) begin

                // do nothing

            end


            // ------------------------------------------------------------
            // LF: 涓�琛岀粨鏉燂紝瑙ｆ瀽鍛戒护骞朵骇鐢� ACK / ERR
            // ------------------------------------------------------------

            else if (pc_rx_data == 8'h0A) begin

                cmd_response_pulse <= 1'b1;

                cmd_response_ok <=
                    cmd_recognized;

                cmd_response_len <=
                    pc_cmd_len;

                cmd_response_line <=
                    pc_cmd_line;


                // --------------------------------------------------------
                // TEST
                // --------------------------------------------------------

                if (cmd_test) begin

                    // 浠呯敤浜庨摼璺祴璇曪紝涓嶆敼鍙樻帶鍒剁姸鎬�

                end


                // --------------------------------------------------------
                // STEP
                // --------------------------------------------------------

                else if (cmd_step_start) begin

                    step_running <= 1'b1;

                    if (step_direction == DIR_STOP)
                        step_direction <= DIR_FWD;

                end
                else if (cmd_step_stop) begin

                    step_running <= 1'b0;
                    step_direction <= DIR_STOP;

                end
                else if (cmd_step_cw) begin

                    step_direction <= DIR_FWD;

                end
                else if (cmd_step_ccw) begin

                    step_direction <= DIR_REV;

                end
                else if (cmd_step_speed) begin

                    step_speed <=
                        parsed_step_speed[3:0];

                end


                // --------------------------------------------------------
                // DC
                // --------------------------------------------------------

                else if (cmd_dc_start) begin

                    dc_running <= 1'b1;

                    if (dc_direction == DIR_STOP)
                        dc_direction <= DIR_FWD;

                end
                else if (cmd_dc_stop) begin

                    dc_running <= 1'b0;
                    dc_direction <= DIR_STOP;

                end
                else if (cmd_dc_fwd) begin

                    dc_direction <= DIR_FWD;

                end
                else if (cmd_dc_rev) begin

                    dc_direction <= DIR_REV;

                end
                else if (cmd_dc_pwm) begin

                    dc_pwm <=
                        parsed_dc_pwm[6:0];

                end


                // --------------------------------------------------------
                // EC1
                // --------------------------------------------------------

                else if (cmd_ec1_press) begin

                    ec1_pressed <= 1'b1;

                end
                else if (cmd_ec1_release) begin

                    ec1_pressed <= 1'b0;

                end
                else if (cmd_ec1_value) begin

                    ec1_value <=
                        parsed_ec1_value[6:0];

                end


                // 涓轰笅涓�鏉″懡浠ゆ竻绌虹紦瀛�
                pc_cmd_line <= 256'h0;

                pc_cmd_len <= 6'd0;

            end


            // ------------------------------------------------------------
            // 鏅�� ASCII 瀛楄妭
            // ------------------------------------------------------------

            else begin

                if (pc_cmd_len < 6'd32) begin

                    pc_cmd_line[
                        (pc_cmd_len * 8) +: 8
                    ] <= pc_rx_data;

                    pc_cmd_len <=
                        pc_cmd_len + 1'b1;

                end

            end

        end

    end


    // ========================================================================
    // PC UART TX
    // ========================================================================

    reg [7:0] pc_tx_data  = 8'h00;
    reg       pc_tx_start = 1'b0;

    wire pc_tx_busy;
    wire pc_tx_done;


    ch9350_combo_pc_uart_tx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (PC_BAUD)
    ) u_pc_tx (
        .clk   (sys_clk),
        .data  (pc_tx_data),
        .start (pc_tx_start),

        .tx    (UART_TXD),
        .busy  (pc_tx_busy),
        .done  (pc_tx_done)
    );



    // ========================================================================
    // PC鍙戦�佺姸鎬�
    // ========================================================================

    localparam [2:0]
        TX_IDLE      = 3'd0,
        TX_LOAD      = 3'd1,
        TX_WAIT_BUSY = 3'd2,
        TX_WAIT_DONE = 3'd3;


    reg [2:0] tx_state = TX_IDLE;

    reg [5:0] msg_index = 6'd0;


    // 褰撳墠姝ｅ湪鍙戦�佺殑娑堟伅
    //
    // send_source_cmd = 0:
    //   CH9350 keyboard / mouse
    //
    // send_source_cmd = 1:
    //   PC command ACK / ERR
    reg        send_source_cmd = 1'b0;

    reg [1:0]  send_type    = EV_MOUSE;
    reg [63:0] send_payload = 64'h0;

    reg         send_cmd_ok   = 1'b0;
    reg [5:0]   send_cmd_len  = 6'd0;
    reg [255:0] send_cmd_line = 256'h0;



    // ========================================================================
    // Event FIFO
    //
    // 鍚屼竴涓狥IFO缂撳瓨閿洏銆侀紶鏍囥�佺墿鐞咵C1鍜岀洿娴佺數鏈哄弽棣堟姤鍛�
    //
    // bit65:64 = type
    // bit63:0  = payload
    // ========================================================================

    reg [65:0] event_fifo [0:15];

    reg [3:0] fifo_wr = 4'd0;
    reg [3:0] fifo_rd = 4'd0;

    reg [4:0] fifo_count = 5'd0;


    wire fifo_empty =
        (fifo_count == 0);

    wire fifo_full =
        (fifo_count == 16);


    // ========================================================================
    // Command response FIFO
    //
    // bit262      = 1: ACK, 0: ERR
    // bit261:256  = original command length
    // bit255:0    = original command text
    // ========================================================================

    reg [262:0] cmd_fifo [0:15];

    reg [3:0] cmd_fifo_wr = 4'd0;
    reg [3:0] cmd_fifo_rd = 4'd0;

    reg [4:0] cmd_fifo_count = 5'd0;


    wire cmd_fifo_empty =
        (cmd_fifo_count == 0);

    wire cmd_fifo_full =
        (cmd_fifo_count == 16);


    // 浼樺厛淇濊瘉 CH9350 閿洏榧犳爣瀹炴椂鎬с��
    // 褰� Event FIFO 涓虹┖鏃跺啀鍙戦�� ACK / ERR銆�
    wire pop_event =
        (tx_state == TX_IDLE) &&
        (!fifo_empty) &&
        (!pc_tx_busy);


    wire pop_cmd =
        (tx_state == TX_IDLE) &&
        (fifo_empty) &&
        (!cmd_fifo_empty) &&
        (!pc_tx_busy);


    wire push_ch_event =
        event_pulse &&
        (!fifo_full);


    // CH9350 events have priority if both sources change on the same clock.
    // EC1 keeps its latest pending report until a following FIFO slot is free.
    wire push_ec_event =
        ec1_report_pending &&
        ec1_rst_n &&
        (!fifo_full) &&
        (!event_pulse);


    // DC report is lower priority than CH9350 and EC1, but it remains pending
    // until the FIFO accepts the newest telemetry snapshot.
    wire push_dc_event =
        dc_report_pending &&
        (!fifo_full) &&
        (!event_pulse) &&
        (!(ec1_report_pending && ec1_rst_n));


    wire push_event =
        push_ch_event || push_ec_event || push_dc_event;


    assign ec1_report_consumed =
        push_ec_event;

    assign dc_report_consumed =
        push_dc_event;


    wire push_cmd =
        cmd_response_pulse &&
        (!cmd_fifo_full);


    // ========================================================================
    // FIFO
    // ========================================================================

    always @(posedge sys_clk) begin

        // --------------------------------------------------------
        // 鍐橣IFO
        // --------------------------------------------------------

        if (push_event) begin

            if (push_ch_event)
                event_fifo[fifo_wr] <= {
                    event_type,
                    event_payload
                };
            else if (push_ec_event)
                event_fifo[fifo_wr] <= {
                    EV_EC1,
                    ec1_report_payload
                };
            else
                event_fifo[fifo_wr] <= {
                    EV_DC,
                    dc_report_payload
                };

            fifo_wr <= fifo_wr + 1'b1;

        end


        // --------------------------------------------------------
        // 璇籉IFO
        // --------------------------------------------------------

        if (pop_event) begin

            send_type <=
                event_fifo[fifo_rd][65:64];

            send_payload <=
                event_fifo[fifo_rd][63:0];

            fifo_rd <= fifo_rd + 1'b1;

        end


        // --------------------------------------------------------
        // FIFO count
        // --------------------------------------------------------

        case ({
            push_event,
            pop_event
        })

            2'b10:
                fifo_count <= fifo_count + 1'b1;

            2'b01:
                fifo_count <= fifo_count - 1'b1;

            default:
                fifo_count <= fifo_count;

        endcase

    end



    // ========================================================================
    // Command response FIFO
    // ========================================================================

    always @(posedge sys_clk) begin

        // --------------------------------------------------------
        // 鍐� command FIFO
        // --------------------------------------------------------

        if (push_cmd) begin

            cmd_fifo[cmd_fifo_wr] <= {
                cmd_response_ok,
                cmd_response_len,
                cmd_response_line
            };

            cmd_fifo_wr <=
                cmd_fifo_wr + 1'b1;

        end


        // --------------------------------------------------------
        // 璇� command FIFO
        // --------------------------------------------------------

        if (pop_cmd) begin

            send_cmd_ok <=
                cmd_fifo[cmd_fifo_rd][262];

            send_cmd_len <=
                cmd_fifo[cmd_fifo_rd][261:256];

            send_cmd_line <=
                cmd_fifo[cmd_fifo_rd][255:0];

            cmd_fifo_rd <=
                cmd_fifo_rd + 1'b1;

        end


        // --------------------------------------------------------
        // FIFO count
        // --------------------------------------------------------

        case ({
            push_cmd,
            pop_cmd
        })

            2'b10:
                cmd_fifo_count <=
                    cmd_fifo_count + 1'b1;

            2'b01:
                cmd_fifo_count <=
                    cmd_fifo_count - 1'b1;

            default:
                cmd_fifo_count <=
                    cmd_fifo_count;

        endcase

    end



    // ========================================================================
    // ASCII helper
    // ========================================================================

    function [7:0] hex_char;

        input [3:0] value;

        begin

            if (value <= 9)
                hex_char = "0" + value;
            else
                hex_char = "A" + (value - 10);

        end

    endfunction



    function [7:0] abs8;

        input [7:0] value;

        begin

            if (value[7])
                abs8 = (~value) + 8'd1;
            else
                abs8 = value;

        end

    endfunction



    function [7:0] dec_hundred;

        input [7:0] value;

        begin

            dec_hundred =
                "0" + (value / 100);

        end

    endfunction



    function [7:0] dec_ten;

        input [7:0] value;

        begin

            dec_ten =
                "0" + ((value / 10) % 10);

        end

    endfunction



    function [7:0] dec_one;

        input [7:0] value;

        begin

            dec_one =
                "0" + (value % 10);

        end

    endfunction


    // ========================================================================
    // Signed 16-bit decimal helpers for EC1 count
    // ========================================================================

    function [15:0] abs16;

        input [15:0] value;

        begin

            if (value[15])
                abs16 = (~value) + 16'd1;
            else
                abs16 = value;

        end

    endfunction


    function [7:0] dec16_ten_thousand;

        input [15:0] value;

        begin
            dec16_ten_thousand = "0" + ((value / 10000) % 10);
        end

    endfunction


    function [7:0] dec16_thousand;

        input [15:0] value;

        begin
            dec16_thousand = "0" + ((value / 1000) % 10);
        end

    endfunction


    function [7:0] dec16_hundred;

        input [15:0] value;

        begin
            dec16_hundred = "0" + ((value / 100) % 10);
        end

    endfunction


    function [7:0] dec16_ten;

        input [15:0] value;

        begin
            dec16_ten = "0" + ((value / 10) % 10);
        end

    endfunction


    function [7:0] dec16_one;

        input [15:0] value;

        begin
            dec16_one = "0" + (value % 10);
        end

    endfunction



    // ========================================================================
    // Keyboard report byte
    // ========================================================================

    function [7:0] keyboard_byte;

        input [2:0] index;

        begin

            case (index)

                3'd0:
                    keyboard_byte = send_payload[63:56];

                3'd1:
                    keyboard_byte = send_payload[55:48];

                3'd2:
                    keyboard_byte = send_payload[47:40];

                3'd3:
                    keyboard_byte = send_payload[39:32];

                3'd4:
                    keyboard_byte = send_payload[31:24];

                3'd5:
                    keyboard_byte = send_payload[23:16];

                3'd6:
                    keyboard_byte = send_payload[15:8];

                3'd7:
                    keyboard_byte = send_payload[7:0];

                default:
                    keyboard_byte = 8'h00;

            endcase

        end

    endfunction



    // ========================================================================
    // Keyboard ASCII
    //
    // K 00 00 2C 00 00 00 00 00\r\n
    //
    // index 0 ~ 26
    // ========================================================================

    function [7:0] keyboard_message_byte;

        input [5:0] index;

        integer offset;
        integer remainder;

        reg [2:0] byte_index;
        reg [7:0] value;

        begin

            keyboard_message_byte = 8'h00;

            offset    = 0;
            remainder = 0;

            byte_index = 3'd0;
            value      = 8'h00;


            if (index == 6'd0) begin

                keyboard_message_byte = "K";

            end
            else if (index == 6'd1) begin

                keyboard_message_byte = " ";

            end
            else if (
                (index >= 6'd2) &&
                (index <= 6'd24)
            ) begin

                offset =
                    index - 6'd2;

                byte_index =
                    offset / 3;

                remainder =
                    offset % 3;

                value =
                    keyboard_byte(
                        byte_index
                    );


                if (remainder == 0) begin

                    keyboard_message_byte =
                        hex_char(
                            value[7:4]
                        );

                end
                else if (remainder == 1) begin

                    keyboard_message_byte =
                        hex_char(
                            value[3:0]
                        );

                end
                else begin

                    // 鏈�鍚庝竴涓猙yte鍚庨潰娌℃湁绌烘牸
                    if (byte_index < 7)
                        keyboard_message_byte = " ";
                    else
                        keyboard_message_byte = 8'h00;

                end

            end
            else if (index == 6'd25) begin

                keyboard_message_byte =
                    8'h0D;

            end
            else if (index == 6'd26) begin

                keyboard_message_byte =
                    8'h0A;

            end

        end

    endfunction



    // ========================================================================
    // Mouse ASCII
    //
    // M B=01 X=+003 Y=-002 W=+000\r\n
    //
    // index 0 ~ 28
    // ========================================================================

    function [7:0] mouse_message_byte;

        input [5:0] index;

        reg [7:0] button;
        reg [7:0] x_value;
        reg [7:0] y_value;
        reg [7:0] w_value;

        reg [7:0] x_mag;
        reg [7:0] y_mag;
        reg [7:0] w_mag;

        begin

            button =
                send_payload[31:24];

            x_value =
                send_payload[23:16];

            y_value =
                send_payload[15:8];

            w_value =
                send_payload[7:0];


            x_mag = abs8(x_value);
            y_mag = abs8(y_value);
            w_mag = abs8(w_value);


            case (index)

                6'd0:
                    mouse_message_byte = "M";

                6'd1:
                    mouse_message_byte = " ";

                6'd2:
                    mouse_message_byte = "B";

                6'd3:
                    mouse_message_byte = "=";

                6'd4:
                    mouse_message_byte =
                        hex_char(
                            button[7:4]
                        );

                6'd5:
                    mouse_message_byte =
                        hex_char(
                            button[3:0]
                        );

                6'd6:
                    mouse_message_byte = " ";


                // X
                6'd7:
                    mouse_message_byte = "X";

                6'd8:
                    mouse_message_byte = "=";

                6'd9:
                    mouse_message_byte =
                        x_value[7] ? "-" : "+";

                6'd10:
                    mouse_message_byte =
                        dec_hundred(x_mag);

                6'd11:
                    mouse_message_byte =
                        dec_ten(x_mag);

                6'd12:
                    mouse_message_byte =
                        dec_one(x_mag);

                6'd13:
                    mouse_message_byte = " ";


                // Y
                6'd14:
                    mouse_message_byte = "Y";

                6'd15:
                    mouse_message_byte = "=";

                6'd16:
                    mouse_message_byte =
                        y_value[7] ? "-" : "+";

                6'd17:
                    mouse_message_byte =
                        dec_hundred(y_mag);

                6'd18:
                    mouse_message_byte =
                        dec_ten(y_mag);

                6'd19:
                    mouse_message_byte =
                        dec_one(y_mag);

                6'd20:
                    mouse_message_byte = " ";


                // Wheel
                6'd21:
                    mouse_message_byte = "W";

                6'd22:
                    mouse_message_byte = "=";

                6'd23:
                    mouse_message_byte =
                        w_value[7] ? "-" : "+";

                6'd24:
                    mouse_message_byte =
                        dec_hundred(w_mag);

                6'd25:
                    mouse_message_byte =
                        dec_ten(w_mag);

                6'd26:
                    mouse_message_byte =
                        dec_one(w_mag);


                6'd27:
                    mouse_message_byte =
                        8'h0D;

                6'd28:
                    mouse_message_byte =
                        8'h0A;


                default:
                    mouse_message_byte =
                        8'h00;

            endcase

        end

    endfunction



    // ========================================================================
    // Physical EC1 ASCII
    //
    // E C=+00001 D=+ K=0\r\n
    // E C=-00001 D=- K=0\r\n
    // E C=+00000 D=0 K=1\r\n
    //
    // index 0 ~ 19
    // ========================================================================

    function [7:0] ec1_message_byte;

        input [5:0] index;

        reg [15:0] count_value;
        reg [15:0] count_magnitude;
        reg [1:0]  direction_value;
        reg        key_value;

        begin

            count_value = send_payload[63:48];
            direction_value = send_payload[47:46];
            key_value = send_payload[45];
            count_magnitude = abs16(count_value);

            case (index)

                6'd0:  ec1_message_byte = "E";
                6'd1:  ec1_message_byte = " ";
                6'd2:  ec1_message_byte = "C";
                6'd3:  ec1_message_byte = "=";
                6'd4:  ec1_message_byte = count_value[15] ? "-" : "+";
                6'd5:  ec1_message_byte = dec16_ten_thousand(count_magnitude);
                6'd6:  ec1_message_byte = dec16_thousand(count_magnitude);
                6'd7:  ec1_message_byte = dec16_hundred(count_magnitude);
                6'd8:  ec1_message_byte = dec16_ten(count_magnitude);
                6'd9:  ec1_message_byte = dec16_one(count_magnitude);
                6'd10: ec1_message_byte = " ";
                6'd11: ec1_message_byte = "D";
                6'd12: ec1_message_byte = "=";
                6'd13: begin
                    if (direction_value == EC_DIR_CW)
                        ec1_message_byte = "+";
                    else if (direction_value == EC_DIR_CCW)
                        ec1_message_byte = "-";
                    else
                        ec1_message_byte = "0";
                end
                6'd14: ec1_message_byte = " ";
                6'd15: ec1_message_byte = "K";
                6'd16: ec1_message_byte = "=";
                6'd17: ec1_message_byte = key_value ? "1" : "0";
                6'd18: ec1_message_byte = 8'h0D;
                6'd19: ec1_message_byte = 8'h0A;

                default:
                    ec1_message_byte = 8'h00;

            endcase

        end

    endfunction



    // ========================================================================
    // DC motor optical-feedback ASCII
    //
    // D Q=89ABCDEF R=0123 P=050 L=1 I=0 S=1 D=1\r\n
    //
    // Q: accumulated quarter-turn count, 8 hexadecimal digits
    // R: measured RPM, four decimal digits
    // P: requested PWM duty, 000..100
    // L: physical DC_MOTOR_LED state (1 = lit)
    // I: 3-second direction-interlock state
    // S: actual motor running state
    // D: direction applied to bridge (0=stop, 1=forward, 2=reverse)
    // index 0 ~ 42
    // ========================================================================

    function [7:0] dc_message_byte;

        input [5:0] index;

        reg [31:0] quarter_count_value;
        reg [15:0] rpm_value;
        reg [7:0]  pwm_value;
        reg        led_value;
        reg        interlock_value;
        reg        running_value;
        reg [1:0]  direction_value;

        begin

            quarter_count_value = send_payload[63:32];
            rpm_value           = send_payload[31:16];
            pwm_value           = {1'b0, send_payload[15:9]};
            led_value           = send_payload[8];
            interlock_value     = send_payload[7];
            running_value       = send_payload[6];
            direction_value     = send_payload[5:4];

            case (index)

                6'd0:  dc_message_byte = "D";
                6'd1:  dc_message_byte = " ";
                6'd2:  dc_message_byte = "Q";
                6'd3:  dc_message_byte = "=";
                6'd4:  dc_message_byte = hex_char(quarter_count_value[31:28]);
                6'd5:  dc_message_byte = hex_char(quarter_count_value[27:24]);
                6'd6:  dc_message_byte = hex_char(quarter_count_value[23:20]);
                6'd7:  dc_message_byte = hex_char(quarter_count_value[19:16]);
                6'd8:  dc_message_byte = hex_char(quarter_count_value[15:12]);
                6'd9:  dc_message_byte = hex_char(quarter_count_value[11:8]);
                6'd10: dc_message_byte = hex_char(quarter_count_value[7:4]);
                6'd11: dc_message_byte = hex_char(quarter_count_value[3:0]);
                6'd12: dc_message_byte = " ";
                6'd13: dc_message_byte = "R";
                6'd14: dc_message_byte = "=";
                6'd15: dc_message_byte = dec16_thousand(rpm_value);
                6'd16: dc_message_byte = dec16_hundred(rpm_value);
                6'd17: dc_message_byte = dec16_ten(rpm_value);
                6'd18: dc_message_byte = dec16_one(rpm_value);
                6'd19: dc_message_byte = " ";
                6'd20: dc_message_byte = "P";
                6'd21: dc_message_byte = "=";
                6'd22: dc_message_byte = dec_hundred(pwm_value);
                6'd23: dc_message_byte = dec_ten(pwm_value);
                6'd24: dc_message_byte = dec_one(pwm_value);
                6'd25: dc_message_byte = " ";
                6'd26: dc_message_byte = "L";
                6'd27: dc_message_byte = "=";
                6'd28: dc_message_byte = led_value ? "1" : "0";
                6'd29: dc_message_byte = " ";
                6'd30: dc_message_byte = "I";
                6'd31: dc_message_byte = "=";
                6'd32: dc_message_byte = interlock_value ? "1" : "0";
                6'd33: dc_message_byte = " ";
                6'd34: dc_message_byte = "S";
                6'd35: dc_message_byte = "=";
                6'd36: dc_message_byte = running_value ? "1" : "0";
                6'd37: dc_message_byte = " ";
                6'd38: dc_message_byte = "D";
                6'd39: dc_message_byte = "=";
                6'd40: dc_message_byte = "0" + {6'd0, direction_value};
                6'd41: dc_message_byte = 8'h0D;
                6'd42: dc_message_byte = 8'h0A;

                default:
                    dc_message_byte = 8'h00;

            endcase

        end

    endfunction



    // ========================================================================
    // PC command response ASCII
    //
    // ACK <command>\r\n
    // ERR <command>\r\n
    //
    // index:
    // 0..2  ACK / ERR
    // 3     space
    // 4..   original command
    // last-1 CR
    // last   LF
    // ========================================================================

    function [7:0] command_line_byte;

        input [5:0] index;

        begin

            command_line_byte =
                send_cmd_line[
                    (index * 8) +: 8
                ];

        end

    endfunction


    function [7:0] command_message_byte;

        input [5:0] index;

        begin

            if (index == 6'd0)
                command_message_byte =
                    send_cmd_ok ? "A" : "E";

            else if (index == 6'd1)
                command_message_byte =
                    send_cmd_ok ? "C" : "R";

            else if (index == 6'd2)
                command_message_byte =
                    send_cmd_ok ? "K" : "R";

            else if (index == 6'd3)
                command_message_byte = " ";

            else if (
                (index >= 6'd4) &&
                (index < (6'd4 + send_cmd_len))
            )
                command_message_byte =
                    command_line_byte(
                        index - 6'd4
                    );

            else if (
                index ==
                (6'd4 + send_cmd_len)
            )
                command_message_byte =
                    8'h0D;

            else
                command_message_byte =
                    8'h0A;

        end

    endfunction



    // ========================================================================
    // 褰撳墠娑堟伅瀛楄妭
    // ========================================================================

    function [7:0] current_message_byte;

        input [5:0] index;

        begin

            if (send_source_cmd)
                current_message_byte =
                    command_message_byte(index);

            else if (send_type == EV_KEYBOARD)
                current_message_byte =
                    keyboard_message_byte(index);

            else if (send_type == EV_EC1)
                current_message_byte =
                    ec1_message_byte(index);

            else if (send_type == EV_DC)
                current_message_byte =
                    dc_message_byte(index);

            else
                current_message_byte =
                    mouse_message_byte(index);

        end

    endfunction



    wire [5:0] message_last_index =
        send_source_cmd
            ? (send_cmd_len + 6'd5)
            : (
                (send_type == EV_KEYBOARD)
                    ? 6'd26
                    : (
                        (send_type == EV_EC1)
                            ? 6'd19
                            : (
                                (send_type == EV_DC)
                                    ? 6'd42
                                    : 6'd28
                              )
                      )
              );



    // ========================================================================
    // ASCII UART TX FSM
    // ========================================================================

    always @(posedge sys_clk) begin

        pc_tx_start <= 1'b0;


        case (tx_state)

            // --------------------------------------------------------
            // 绛夊緟FIFO浜嬩欢
            // --------------------------------------------------------

            TX_IDLE: begin

                if (pop_event) begin

                    send_source_cmd <= 1'b0;

                    msg_index <= 6'd0;

                    tx_state <= TX_LOAD;

                end
                else if (pop_cmd) begin

                    send_source_cmd <= 1'b1;

                    msg_index <= 6'd0;

                    tx_state <= TX_LOAD;

                end

            end


            // --------------------------------------------------------
            // 瑁呰浇瀛楃
            // --------------------------------------------------------

            TX_LOAD: begin

                if (!pc_tx_busy) begin

                    pc_tx_data <=
                        current_message_byte(
                            msg_index
                        );

                    pc_tx_start <= 1'b1;

                    tx_state <=
                        TX_WAIT_BUSY;

                end

            end


            // --------------------------------------------------------
            // 绛夊緟TX杩涘叆busy
            // --------------------------------------------------------

            TX_WAIT_BUSY: begin

                if (pc_tx_busy)
                    tx_state <=
                        TX_WAIT_DONE;

            end


            // --------------------------------------------------------
            // 绛夊緟褰撳墠瀛楃鍙戦�佺粨鏉�
            // --------------------------------------------------------

            TX_WAIT_DONE: begin

                if (pc_tx_done) begin

                    if (
                        msg_index ==
                        message_last_index
                    ) begin

                        tx_state <=
                            TX_IDLE;

                    end
                    else begin

                        msg_index <=
                            msg_index + 1'b1;

                        tx_state <=
                            TX_LOAD;

                    end

                end

            end


            default: begin

                tx_state <= TX_IDLE;

            end

        endcase

    end



    // ========================================================================
    // Stepper motor hardware drive
    //
    // Baseboard signals:
    //   I_SETP_MOTOR_BA / BB / BC / BD
    //
    // 6-wire unipolar stepper:
    //   BA, BC are the two ends of winding A
    //   BB, BD are the two ends of winding B
    //
    // Half-step sequence {BA,BB,BC,BD}:
    //   1000 -> 1100 -> 0100 -> 0110
    //   0010 -> 0011 -> 0001 -> 1001
    //
    // STEP CW   : phase index +1
    // STEP CCW  : phase index -1
    // STEP STOP : all four outputs low
    //
    // Speed 1..10 maps to about 20ms..2ms per half-step at 100MHz.
    // ========================================================================

    reg [2:0]  step_phase   = 3'd0;
    reg [31:0] step_div_cnt = 32'd0;


    function [31:0] step_interval_cycles;

        input [3:0] speed;

        begin

            case (speed)

                4'd1:  step_interval_cycles = 32'd2_000_000; // 20 ms
                4'd2:  step_interval_cycles = 32'd1_800_000; // 18 ms
                4'd3:  step_interval_cycles = 32'd1_600_000; // 16 ms
                4'd4:  step_interval_cycles = 32'd1_400_000; // 14 ms
                4'd5:  step_interval_cycles = 32'd1_200_000; // 12 ms
                4'd6:  step_interval_cycles = 32'd1_000_000; // 10 ms
                4'd7:  step_interval_cycles = 32'd800_000;   // 8 ms
                4'd8:  step_interval_cycles = 32'd600_000;   // 6 ms
                4'd9:  step_interval_cycles = 32'd400_000;   // 4 ms
                4'd10: step_interval_cycles = 32'd200_000;   // 2 ms

                default:
                    step_interval_cycles = 32'd1_200_000;

            endcase

        end

    endfunction


    function [3:0] step_phase_pattern;

        input [2:0] phase;

        begin

            case (phase)

                3'd0: step_phase_pattern = 4'b1000;
                3'd1: step_phase_pattern = 4'b1100;
                3'd2: step_phase_pattern = 4'b0100;
                3'd3: step_phase_pattern = 4'b0110;
                3'd4: step_phase_pattern = 4'b0010;
                3'd5: step_phase_pattern = 4'b0011;
                3'd6: step_phase_pattern = 4'b0001;
                3'd7: step_phase_pattern = 4'b1001;

                default:
                    step_phase_pattern = 4'b0000;

            endcase

        end

    endfunction


    wire [31:0] step_interval =
        step_interval_cycles(step_speed);


    wire [3:0] step_drive =
        (step_running && (step_direction != DIR_STOP))
            ? step_phase_pattern(step_phase)
            : 4'b0000;


    assign I_SETP_MOTOR_BA = step_drive[3];
    assign I_SETP_MOTOR_BB = step_drive[2];
    assign I_SETP_MOTOR_BC = step_drive[1];
    assign I_SETP_MOTOR_BD = step_drive[0];
    
    // =====================================================
    // DC Motor Drive
    // =====================================================

    // PWM鍛ㄦ湡
    reg [15:0] dc_pwm_cnt = 16'd0;


    always @(posedge sys_clk)
    begin

        dc_pwm_cnt <= dc_pwm_cnt + 1'b1;

    end



    // =====================================================
    // DC Motor PWM
    // =====================================================

    wire dc_pwm_level;
    wire dc_bridge_enable;
    wire dc_drive_pwm;

    // Requested direction (dc_direction) is separated from the direction
    // actually applied to the H bridge.  When a running motor changes
    // direction, both direction inputs and PWM are first disabled for
    // 3 seconds.  This prevents an immediate forward/reverse shoot-through
    // and gives the motor enough time to coast to a stop before reversal.
    localparam integer DC_DEADTIME_MS = 3000;
    localparam integer DC_DEADTIME_CYCLES =
        (CLK_HZ / 1000) * DC_DEADTIME_MS;

    reg [1:0]  dc_applied_direction = DIR_STOP;
    reg [1:0]  dc_pending_direction = DIR_STOP;
    reg [31:0] dc_deadtime_count    = 32'd0;
    reg        dc_interlock_active  = 1'b0;

    always @(posedge sys_clk) begin
        // STOP always removes both direction signals immediately.
        if (!dc_running || (dc_direction == DIR_STOP)) begin
            dc_applied_direction <= DIR_STOP;
            dc_pending_direction <= dc_direction;
            dc_deadtime_count    <= 32'd0;
            dc_interlock_active  <= 1'b0;
        end
        else if (dc_interlock_active) begin
            // Keep the bridge disabled throughout the dead time.
            dc_applied_direction <= DIR_STOP;

            // If another direction command arrives during the dead time,
            // restart the dead time for the newest requested direction.
            if (dc_direction != dc_pending_direction) begin
                dc_pending_direction <= dc_direction;
                dc_deadtime_count    <= DC_DEADTIME_CYCLES;
            end
            else if (dc_deadtime_count > 32'd1) begin
                dc_deadtime_count <= dc_deadtime_count - 1'b1;
            end
            else begin
                dc_deadtime_count    <= 32'd0;
                dc_interlock_active  <= 1'b0;
                dc_applied_direction <= dc_pending_direction;
            end
        end
        else if (dc_applied_direction == DIR_STOP) begin
            // Starting from a stopped bridge is safe without an extra delay.
            dc_applied_direction <= dc_direction;
            dc_pending_direction <= dc_direction;
        end
        else if (dc_applied_direction != dc_direction) begin
            // Running direction reversal: first force the bridge off.
            dc_applied_direction <= DIR_STOP;
            dc_pending_direction <= dc_direction;
            dc_deadtime_count    <= DC_DEADTIME_CYCLES;
            dc_interlock_active  <= 1'b1;
        end
    end

    // Internal positive-duty PWM:
    // 0% = always low, 100% = always high.
    assign dc_pwm_level =
            (dc_pwm == 7'd0)   ? 1'b0 :
            (dc_pwm >= 7'd100) ? 1'b1 :
            (dc_pwm_cnt < (dc_pwm * 16'd655));

    // Enable the bridge only when the requested direction has passed the
    // three-second reversal interlock.
    assign dc_bridge_enable =
            (EC1_HW_MODE == 0) &&
            dc_running &&
            !dc_interlock_active &&
            (dc_applied_direction == dc_direction) &&
            (dc_applied_direction != DIR_STOP);

    // The PWM remains on the active H-bridge direction input.
    assign dc_drive_pwm =
            dc_bridge_enable && dc_pwm_level;

    // Board H-bridge drive truth table:
    //   STOP/FREE : A=0,   B=0
    //   FORWARD   : A=PWM, B=0
    //   REVERSE   : A=0,   B=PWM
    assign DC_MOTORA =
            dc_drive_pwm &&
            (dc_applied_direction == DIR_FWD);

    // AA19 is the shared EC_B / DC_MOTORB physical pin.  In DC motor mode
    // it becomes the reverse direction output.  In EC1 mode it is released
    // to high impedance so the same pin can be sampled as EC_B.
    wire dc_motor_b_drive =
            dc_drive_pwm &&
            (dc_applied_direction == DIR_REV);

    assign EC_B =
            (EC1_HW_MODE == 0) ? dc_motor_b_drive : 1'bz;

    // =====================================================
    // DC optical speed feedback / physical green indicator
    // =====================================================

    // DC_MOTOR_SPEED is not a PWM output.  It is the shaped output of the
    // baseboard U16 optical slot sensor.  The nearby green LED is active low:
    // feedback=0 means the optical mark is detected and the LED is on.
    //
    // Synchronize the asynchronous sensor signal and require it to remain
    // unchanged for 100 us.  This rejects chatter at a slot boundary without
    // hiding genuine quarter-turn pulses at normal motor speeds.
    localparam integer DC_SPEED_FILTER_CYCLES =
        (CLK_HZ / 10_000 < 2) ? 2 : (CLK_HZ / 10_000);

    (* ASYNC_REG = "TRUE" *) reg [2:0] dc_speed_sync = 3'b111;
    reg        dc_speed_candidate  = 1'b1;
    reg        dc_speed_filtered   = 1'b1;
    reg        dc_speed_filtered_d = 1'b1;
    reg [15:0] dc_speed_stable_cnt = 16'd0;

    always @(posedge sys_clk or negedge ec1_rst_n) begin
        if (!ec1_rst_n) begin
            dc_speed_sync       <= 3'b111;
            dc_speed_candidate  <= 1'b1;
            dc_speed_filtered   <= 1'b1;
            dc_speed_filtered_d <= 1'b1;
            dc_speed_stable_cnt <= 16'd0;
        end
        else begin
            dc_speed_sync       <= {dc_speed_sync[1:0], DC_MOTOR_SPEED};
            dc_speed_filtered_d <= dc_speed_filtered;

            if (dc_speed_sync[2] != dc_speed_candidate) begin
                dc_speed_candidate  <= dc_speed_sync[2];
                dc_speed_stable_cnt <= 16'd0;
            end
            else if (dc_speed_filtered != dc_speed_candidate) begin
                if (dc_speed_stable_cnt >= (DC_SPEED_FILTER_CYCLES - 1)) begin
                    dc_speed_filtered   <= dc_speed_candidate;
                    dc_speed_stable_cnt <= 16'd0;
                end
                else begin
                    dc_speed_stable_cnt <= dc_speed_stable_cnt + 1'b1;
                end
            end
            else begin
                dc_speed_stable_cnt <= 16'd0;
            end
        end
    end

    // Mirrors the actual baseboard LED, including the rotor's stopped
    // position.  The LED may therefore remain on after STOP if a mark is
    // parked in front of the sensor; that is normal hardware behaviour.
    wire dc_motor_led_on = ~dc_speed_filtered;

    // One falling edge is one optical mark.  The board has four marks per
    // revolution, so each accepted pulse represents 1/4 revolution.
    // Count only while the H bridge is actively driving the motor.
    wire dc_quarter_pulse =
        dc_bridge_enable && dc_speed_filtered_d && !dc_speed_filtered;

    wire dc_speed_level_changed =
        dc_speed_filtered_d != dc_speed_filtered;

    reg [31:0] dc_quarter_count = 32'd0;
    reg [15:0] dc_pulses_this_second = 16'd0;
    reg [15:0] dc_measured_rpm = 16'd0;
    reg [31:0] dc_one_second_count = 32'd0;
    reg [31:0] dc_report_interval_count = 32'd0;

    localparam integer DC_ONE_SECOND_CYCLES = CLK_HZ;
    localparam integer DC_REPORT_CYCLES = CLK_HZ; // periodic 1 s report

    always @(posedge sys_clk) begin
        // Pending telemetry is cleared only after the common FIFO accepts it.
        if (dc_report_consumed)
            dc_report_pending <= 1'b0;

        if (dc_quarter_pulse) begin
            dc_quarter_count <= dc_quarter_count + 1'b1;
            dc_pulses_this_second <= dc_pulses_this_second + 1'b1;

            // Send every quarter-turn immediately so Qt can animate the wheel
            // and reproduce the physical LED pulse without waiting 200 ms.
            dc_report_payload <= {
                dc_quarter_count + 1'b1,
                dc_measured_rpm,
                dc_pwm,
                1'b1,
                dc_interlock_active,
                dc_running,
                dc_applied_direction,
                4'b0000
            };
            dc_report_pending <= 1'b1;
        end
        else if (dc_speed_level_changed) begin
            // Send the opposite sensor edge immediately as well, so the Qt
            // lamp follows both the ON and OFF transitions of the physical
            // green LED.  Only the falling edge above increments 1/4 turn.
            dc_report_payload <= {
                dc_quarter_count,
                dc_measured_rpm,
                dc_pwm,
                dc_motor_led_on,
                dc_interlock_active,
                dc_running,
                dc_applied_direction,
                4'b0000
            };
            dc_report_pending <= 1'b1;
        end

        if (dc_one_second_count >= (DC_ONE_SECOND_CYCLES - 1)) begin
            dc_one_second_count <= 32'd0;
            dc_measured_rpm <=
                (dc_pulses_this_second + (dc_quarter_pulse ? 1'b1 : 1'b0)) * 16'd15;
            dc_pulses_this_second <= dc_quarter_pulse ? 16'd1 : 16'd0;
        end
        else begin
            dc_one_second_count <= dc_one_second_count + 1'b1;
        end

        if (dc_report_interval_count >= (DC_REPORT_CYCLES - 1)) begin
            dc_report_interval_count <= 32'd0;
            dc_report_payload <= {
                dc_quarter_count + (dc_quarter_pulse ? 1'b1 : 1'b0),
                dc_measured_rpm,
                dc_pwm,
                dc_motor_led_on,
                dc_interlock_active,
                dc_running,
                dc_applied_direction,
                4'b0000
            };
            dc_report_pending <= 1'b1;
        end
        else begin
            dc_report_interval_count <= dc_report_interval_count + 1'b1;
        end
    end


    always @(posedge sys_clk) begin

        if (
            !step_running ||
            (step_direction == DIR_STOP)
        ) begin

            step_div_cnt <= 32'd0;
            step_phase   <= 3'd0;

        end
        else if (
            step_div_cnt >=
            (step_interval - 1'b1)
        ) begin

            step_div_cnt <= 32'd0;

            if (step_direction == DIR_FWD)
                step_phase <= step_phase + 1'b1;
            else
                step_phase <= step_phase - 1'b1;

        end
        else begin

            step_div_cnt <=
                step_div_cnt + 1'b1;

        end

    end
    
    // ============================================================
    // LED diagnostics
    //
    // EC1_HW_MODE=1:
    //   LED0: EC1 rotation pulse held for about 0.2 second
    //   LED1: selected manual EC1 direction
    //
    // EC1_HW_MODE=0:
    //   LED0: requested reverse direction
    //   LED1: reverse direction is actually being driven
    // ============================================================

    localparam integer EC1_LED_HOLD_CYCLES = CLK_HZ / 5;
    reg [31:0] ec1_led_hold_count = 32'd0;

    always @(posedge sys_clk or negedge ec1_rst_n) begin
        if (!ec1_rst_n)
            ec1_led_hold_count <= 32'd0;
        else if (ec1_rotate_pulse)
            ec1_led_hold_count <= EC1_LED_HOLD_CYCLES;
        else if (ec1_led_hold_count != 0)
            ec1_led_hold_count <= ec1_led_hold_count - 1'b1;
    end

    assign LED0 =
        (EC1_HW_MODE != 0)
            ? (ec1_led_hold_count != 0)
            : (dc_direction == DIR_REV);

    assign LED1 =
        (EC1_HW_MODE != 0)
            ? (ec1_last_dir == EC_DIR_CCW)
            : (dc_running &&
               !dc_interlock_active &&
               (dc_applied_direction == DIR_REV));

endmodule


// ============================================================================
// EC11 single-channel fallback decoder
//
// This module intentionally uses EC_A only.  It cannot determine the physical
// rotation direction; the direction is selected by pressing EC11 in the top.
// One stable falling edge produces one rotation pulse, with a lockout interval
// to reject mechanical contact bounce.
// ============================================================================

module ch9350_ec11_quad_decoder #(
    parameter integer CLK_HZ     = 50_000_000,
    parameter integer LOCKOUT_MS = 20
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ec_a,
    input  wire ec_b,
    output reg  cw_pulse,
    output reg  ccw_pulse
);

    // 50 MHz下连续稳定8个周期，约160 ns。
    // 接触抖动由完整AB相序列判断消除，不使用毫秒级滤波。
    localparam integer FILTER_CYCLES = 8;

    // 两级同步
    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] b_sync;

    wire [1:0] sync_ab = {a_sync[1], b_sync[1]};

    // 稳定状态滤波
    reg [1:0]  candidate_ab;
    reg [1:0]  stable_ab;
    reg [31:0] stable_count;

    // 累计四分之一相位；完整一格包含4个有效相位变化
    reg signed [3:0] phase_accum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_sync <= 2'b11;
            b_sync <= 2'b11;
        end else begin
            a_sync <= {a_sync[0], ec_a};
            b_sync <= {b_sync[0], ec_b};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            candidate_ab <= 2'b11;
            stable_ab    <= 2'b11;
            stable_count <= 32'd0;
            phase_accum  <= 4'sd0;
            cw_pulse   <= 1'b0;
            ccw_pulse     <= 1'b0;
        end else begin
            cw_pulse <= 1'b0;
            ccw_pulse <= 1'b0;

            // 输入状态改变，重新开始稳定计时
            if (sync_ab != candidate_ab) begin
                candidate_ab <= sync_ab;
                stable_count <= 32'd0;

            end else if (candidate_ab != stable_ab) begin
                if (stable_count >= FILTER_CYCLES - 1) begin
                    stable_count <= 32'd0;
                    stable_ab    <= candidate_ab;

                    case ({stable_ab, candidate_ab})

                        // 一个方向：
                        // 11 -> 10 -> 00 -> 01 -> 11
                        4'b1110,
                        4'b1000,
                        4'b0001,
                        4'b0111: begin
                            if (candidate_ab == 2'b11) begin
                                if (phase_accum == 4'sd3) begin
                                    cw_pulse <= 1'b1;
                                    ccw_pulse   <= 1'b0;
                                end
                                phase_accum <= 4'sd0;
                            end else begin
                                phase_accum <= phase_accum + 4'sd1;
                            end
                        end

                        // 另一个方向：
                        // 11 -> 01 -> 00 -> 10 -> 11
                        4'b1101,
                        4'b0100,
                        4'b0010,
                        4'b1011: begin
                            if (candidate_ab == 2'b11) begin
                                if (phase_accum == -4'sd3) begin
                                    cw_pulse <= 1'b1;
                                    ccw_pulse   <= 1'b0;
                                end
                                phase_accum <= 4'sd0;
                            end else begin
                                phase_accum <= phase_accum - 4'sd1;
                            end
                        end

                        // 跳过状态或非法跳变：放弃本次不完整动作
                        default: begin
                            phase_accum <= 4'sd0;
                        end
                    endcase
                end else begin
                    stable_count <= stable_count + 32'd1;
                end
            end else begin
                stable_count <= 32'd0;
            end
        end
    end

endmodule


module ch9350_ec11_single_channel #(
    parameter integer CLK_HZ      = 100_000_000,
    parameter integer DEBOUNCE_MS = 1,
    parameter integer LOCKOUT_MS  = 20
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ec_a,
    output reg  rotate_pulse
);

    localparam integer DEBOUNCE_CYCLES_CALC =
        (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer DEBOUNCE_CYCLES =
        (DEBOUNCE_CYCLES_CALC < 1) ? 1 : DEBOUNCE_CYCLES_CALC;

    localparam integer LOCKOUT_CYCLES_CALC =
        (CLK_HZ / 1000) * LOCKOUT_MS;
    localparam integer LOCKOUT_CYCLES =
        (LOCKOUT_CYCLES_CALC < 1) ? 1 : LOCKOUT_CYCLES_CALC;

    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync;
    reg a_candidate;
    reg a_filtered;
    reg a_filtered_d;
    reg [31:0] stable_count;
    reg [31:0] lockout_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            a_sync <= 2'b11;
        else
            a_sync <= {a_sync[0], ec_a};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_candidate <= 1'b1;
            a_filtered  <= 1'b1;
            stable_count <= 32'd0;
        end
        else if (a_sync[1] != a_candidate) begin
            a_candidate <= a_sync[1];
            stable_count <= 32'd0;
        end
        else if (a_filtered != a_candidate) begin
            if (stable_count >= DEBOUNCE_CYCLES - 1) begin
                a_filtered  <= a_candidate;
                stable_count <= 32'd0;
            end
            else begin
                stable_count <= stable_count + 1'b1;
            end
        end
        else begin
            stable_count <= 32'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_filtered_d <= 1'b1;
            lockout_count <= 32'd0;
            rotate_pulse <= 1'b0;
        end
        else begin
            a_filtered_d <= a_filtered;
            rotate_pulse <= 1'b0;

            if (lockout_count != 0)
                lockout_count <= lockout_count - 1'b1;

            if (a_filtered_d && !a_filtered &&
                (lockout_count == 0)) begin
                rotate_pulse <= 1'b1;
                lockout_count <= LOCKOUT_CYCLES;
            end
        end
    end

endmodule



// ============================================================================
// CH9350 UART RX
// ============================================================================

module ch9350_combo_uart_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
)(
    input  wire      clk,
    input  wire      rx,

    output reg [7:0] data  = 8'h00,
    output reg       valid = 1'b0
);

    localparam integer CLKS_PER_BIT =
        CLK_HZ / BAUD;

    localparam integer HALF_BIT =
        CLKS_PER_BIT / 2;


    localparam [1:0]
        RX_IDLE  = 2'd0,
        RX_START = 2'd1,
        RX_DATA  = 2'd2,
        RX_STOP  = 2'd3;


    reg [1:0] state = RX_IDLE;


    // 杈撳叆鍚屾
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

            // --------------------------------------------------------
            // Idle
            // --------------------------------------------------------

            RX_IDLE: begin

                clk_cnt <= 32'd0;
                bit_cnt <= 3'd0;

                if (rx_d2 == 1'b0)
                    state <= RX_START;

            end


            // --------------------------------------------------------
            // Start
            // --------------------------------------------------------

            RX_START: begin

                if (
                    clk_cnt ==
                    HALF_BIT - 1
                ) begin

                    clk_cnt <= 32'd0;

                    if (rx_d2 == 1'b0)
                        state <= RX_DATA;
                    else
                        state <= RX_IDLE;

                end
                else begin

                    clk_cnt <=
                        clk_cnt + 1'b1;

                end

            end


            // --------------------------------------------------------
            // Data
            // --------------------------------------------------------

            RX_DATA: begin

                if (
                    clk_cnt ==
                    CLKS_PER_BIT - 1
                ) begin

                    clk_cnt <= 32'd0;

                    shift[bit_cnt] <=
                        rx_d2;


                    if (bit_cnt == 3'd7) begin

                        bit_cnt <= 3'd0;

                        state <=
                            RX_STOP;

                    end
                    else begin

                        bit_cnt <=
                            bit_cnt + 1'b1;

                    end

                end
                else begin

                    clk_cnt <=
                        clk_cnt + 1'b1;

                end

            end


            // --------------------------------------------------------
            // Stop
            // --------------------------------------------------------

            RX_STOP: begin

                if (
                    clk_cnt ==
                    CLKS_PER_BIT - 1
                ) begin

                    clk_cnt <= 32'd0;


                    if (rx_d2 == 1'b1) begin

                        data <= shift;
                        valid <= 1'b1;

                    end


                    state <= RX_IDLE;

                end
                else begin

                    clk_cnt <=
                        clk_cnt + 1'b1;

                end

            end


            default: begin

                state <= RX_IDLE;

            end

        endcase

    end

endmodule



// ============================================================================
// PC UART TX
// ============================================================================

module ch9350_combo_pc_uart_tx #(
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

    localparam integer CLKS_PER_BIT =
        CLK_HZ / BAUD;


    localparam [2:0]
        TX_IDLE  = 3'd0,
        TX_START = 3'd1,
        TX_DATA  = 3'd2,
        TX_STOP  = 3'd3;


    reg [2:0] state =
        TX_IDLE;


    reg [31:0] clk_cnt =
        32'd0;

    reg [2:0] bit_cnt =
        3'd0;

    reg [7:0] shift =
        8'h00;


    always @(posedge clk) begin

        done <= 1'b0;


        case (state)

            // --------------------------------------------------------
            // Idle
            // --------------------------------------------------------

            TX_IDLE: begin

                tx      <= 1'b1;
                busy    <= 1'b0;

                clk_cnt <= 32'd0;
                bit_cnt <= 3'd0;


                if (start) begin

                    shift <= data;

                    tx   <= 1'b0;
                    busy <= 1'b1;

                    state <=
                        TX_START;

                end

            end


            // --------------------------------------------------------
            // Start bit
            // --------------------------------------------------------

            TX_START: begin

                busy <= 1'b1;


                if (
                    clk_cnt ==
                    CLKS_PER_BIT - 1
                ) begin

                    clk_cnt <= 32'd0;

                    tx <= shift[0];

                    state <=
                        TX_DATA;

                end
                else begin

                    clk_cnt <=
                        clk_cnt + 1'b1;

                end

            end


            // --------------------------------------------------------
            // Data bits
            // --------------------------------------------------------

            TX_DATA: begin

                busy <= 1'b1;


                if (
                    clk_cnt ==
                    CLKS_PER_BIT - 1
                ) begin

                    clk_cnt <= 32'd0;


                    if (bit_cnt == 3'd7) begin

                        tx <= 1'b1;

                        state <=
                            TX_STOP;

                    end
                    else begin

                        bit_cnt <=
                            bit_cnt + 1'b1;

                        tx <=
                            shift[
                                bit_cnt + 1'b1
                            ];

                    end

                end
                else begin

                    clk_cnt <=
                        clk_cnt + 1'b1;

                end

            end


            // --------------------------------------------------------
            // Stop bit
            // --------------------------------------------------------

            TX_STOP: begin

                busy <= 1'b1;


                if (
                    clk_cnt ==
                    CLKS_PER_BIT - 1
                ) begin

                    clk_cnt <= 32'd0;

                    tx   <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;

                    state <=
                        TX_IDLE;

                end
                else begin

                    clk_cnt <=
                        clk_cnt + 1'b1;

                end

            end


            default: begin

                state <= TX_IDLE;

                tx   <= 1'b1;
                busy <= 1'b0;

            end

        endcase

    end

endmodule



// ============================================================================
// Physical EC11 true bidirectional quadrature decoder
//
// 姝ｅ悜瀹屾暣搴忓垪锛�11 -> 10 -> 00 -> 01 -> 11
// 鍙嶅悜瀹屾暣搴忓垪锛�11 -> 01 -> 00 -> 10 -> 11
//
// 姣忓畬鎴愪竴涓畬鏁村洓鐩稿懆鏈燂紝鍙緭鍑轰竴涓柟鍚戣剦鍐层��
// 鎺ョ偣鎶栧姩閫犳垚鐨勬鍙嶈烦鍙樹細浜掔浉鎶垫秷锛屼笉浼氳璇垽涓哄彟涓�鏂瑰悜銆�
// ============================================================================

module ch9350_ec11_decoder #(
    parameter integer CLK_HZ      = 100_000_000,
    parameter integer LOCKOUT_MS  = 20,  // 淇濈暀锛屽吋瀹瑰師椤跺眰鍙傛暟
    parameter integer DIR_INVERT  = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ec_a,
    input  wire ec_b,
    output reg  cw_pulse,
    output reg  ccw_pulse
);

    // ============================================================
    // EC_A銆丒C_B寮傛杈撳叆鍚屾
    // ============================================================

    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] b_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_sync <= 2'b11;
            b_sync <= 2'b11;
        end
        else begin
            a_sync <= {a_sync[0], ec_a};
            b_sync <= {b_sync[0], ec_b};
        end
    end


    // ============================================================
    // 涓夋杩炵画閲囨牱婊ゆ尝
    // ============================================================

    reg [2:0] a_history;
    reg [2:0] b_history;

    reg a_level;
    reg b_level;

    wire [2:0] a_history_next =
        {a_history[1:0], a_sync[1]};

    wire [2:0] b_history_next =
        {b_history[1:0], b_sync[1]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_history <= 3'b111;
            b_history <= 3'b111;
            a_level   <= 1'b1;
            b_level   <= 1'b1;
        end
        else begin
            a_history <= a_history_next;
            b_history <= b_history_next;

            if (a_history_next == 3'b111)
                a_level <= 1'b1;
            else if (a_history_next == 3'b000)
                a_level <= 1'b0;

            if (b_history_next == 3'b111)
                b_level <= 1'b1;
            else if (b_history_next == 3'b000)
                b_level <= 1'b0;
        end
    end


    // ============================================================
    // AB鐩哥姸鎬佽浆鎹㈡柟鍚戣〃
    // ============================================================

    reg [1:0] ab_previous;

    wire [1:0] ab_now = {a_level, b_level};

    reg signed [2:0] transition_delta;
    reg signed [3:0] transition_accumulator;

    always @(*) begin
        transition_delta = 3'sd0;

        case ({ab_previous, ab_now})

            // 姝ｆ柟鍚戯細
            // 11 -> 10 -> 00 -> 01 -> 11
            4'b1110,
            4'b1000,
            4'b0001,
            4'b0111:
                transition_delta = 3'sd1;

            // 鍙嶆柟鍚戯細
            // 11 -> 01 -> 00 -> 10 -> 11
            4'b1101,
            4'b0100,
            4'b0010,
            4'b1011:
                transition_delta = -3'sd1;

            default:
                transition_delta = 3'sd0;

        endcase
    end

    wire ab_changed =
        (ab_now != ab_previous);

    wire invalid_transition =
        ab_changed &&
        (transition_delta == 3'sd0);


    // ============================================================
    // 绱鍥涙鏈夋晥鐩镐綅杞崲锛岃緭鍑轰竴涓。浣嶈剦鍐�
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_previous            <= 2'b11;
            transition_accumulator <= 4'sd0;
            cw_pulse               <= 1'b0;
            ccw_pulse              <= 1'b0;
        end
        else begin
            cw_pulse  <= 1'b0;
            ccw_pulse <= 1'b0;

            if (ab_changed) begin

                if (invalid_transition) begin
                    // 渚嬪11鐩存帴璺冲埌00锛岃涓烘槸骞叉壈骞堕噸鏂板紑濮�
                    transition_accumulator <= 4'sd0;
                end
                else if (transition_delta == 3'sd1) begin

                    if (transition_accumulator >= 4'sd3) begin
                        transition_accumulator <= 4'sd0;

                        if (DIR_INVERT != 0)
                            ccw_pulse <= 1'b1;
                        else
                            cw_pulse <= 1'b1;
                    end
                    else begin
                        transition_accumulator <=
                            transition_accumulator + 4'sd1;
                    end
                end
                else if (transition_delta == -3'sd1) begin

                    if (transition_accumulator <= -4'sd3) begin
                        transition_accumulator <= 4'sd0;

                        if (DIR_INVERT != 0)
                            cw_pulse <= 1'b1;
                        else
                            ccw_pulse <= 1'b1;
                    end
                    else begin
                        transition_accumulator <=
                            transition_accumulator - 4'sd1;
                    end
                end

                ab_previous <= ab_now;
            end
        end
    end

endmodule


// ============================================================================
// Board-compatible EC11 bidirectional decoder
//
// Direction is decoded from adjacent Gray-code transitions:
//   positive: 11->10, 10->00, 00->01, 01->11
//   negative: 11->01, 01->00, 00->10, 10->11
//
// The synchronized A/B pair must remain unchanged for FILTER_MS before it is
// accepted. A direction pulse is emitted only after a complete movement leaves
// the mechanical detent state 11 and returns to 11. Contact bounce therefore
// adds opposite transitions that cancel instead of becoming a false direction.
// ============================================================================

module ch9350_ec11_compat_direction #(
    parameter integer CLK_HZ      = 100_000_000,
    parameter integer LOCKOUT_MS  = 1,
    parameter integer DIR_INVERT  = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire ec_a,
    input  wire ec_b,
    output reg  cw_pulse,
    output reg  ccw_pulse
);

    // LOCKOUT_MS is retained in the public interface for compatibility. In
    // this decoder it is the minimum stable time of the A/B pair.
    localparam integer FILTER_CYCLES_CALC =
        (CLK_HZ / 1000) * LOCKOUT_MS;
    localparam integer FILTER_CYCLES =
        (FILTER_CYCLES_CALC < 1) ? 1 : FILTER_CYCLES_CALC;

    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] b_sync;

    wire [1:0] ab_synchronized = {a_sync[1], b_sync[1]};

    reg [1:0]  ab_candidate;
    reg [1:0]  ab_filtered;
    reg [31:0] stable_count;

    reg [1:0] ab_previous;
    reg signed [3:0] transition_sum;
    reg left_detent;

    reg signed [2:0] transition_delta;

    always @(*) begin
        transition_delta = 3'sd0;

        case ({ab_previous, ab_filtered})
            // 11 -> 10 -> 00 -> 01 -> 11
            4'b1110,
            4'b1000,
            4'b0001,
            4'b0111:
                transition_delta = 3'sd1;

            // 11 -> 01 -> 00 -> 10 -> 11
            4'b1101,
            4'b0100,
            4'b0010,
            4'b1011:
                transition_delta = -3'sd1;

            default:
                transition_delta = 3'sd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_sync <= 2'b11;
            b_sync <= 2'b11;
        end
        else begin
            a_sync <= {a_sync[0], ec_a};
            b_sync <= {b_sync[0], ec_b};
        end
    end

    // Millisecond-scale pair debounce. The old three-clock history was only
    // about 30 ns at 100 MHz and could not reject mechanical contact bounce.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_candidate <= 2'b11;
            ab_filtered  <= 2'b11;
            stable_count <= 32'd0;
        end
        else if (ab_synchronized != ab_candidate) begin
            ab_candidate <= ab_synchronized;
            stable_count <= 32'd0;
        end
        else if (ab_filtered != ab_candidate) begin
            if (stable_count >= FILTER_CYCLES - 1) begin
                ab_filtered  <= ab_candidate;
                stable_count <= 32'd0;
            end
            else begin
                stable_count <= stable_count + 1'b1;
            end
        end
        else begin
            stable_count <= 32'd0;
        end
    end

    // Accumulate only legal adjacent Gray transitions. One event is reported
    // at the next stable 11 detent; a bounce excursion normally sums to zero.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_previous  <= 2'b11;
            transition_sum <= 4'sd0;
            left_detent  <= 1'b0;
            cw_pulse     <= 1'b0;
            ccw_pulse    <= 1'b0;
        end
        else begin
            cw_pulse  <= 1'b0;
            ccw_pulse <= 1'b0;

            if (ab_filtered != ab_previous) begin
                // A two-bit jump is not a legal quadrature transition. Drop
                // the incomplete movement and re-arm at the next 11 detent.
                if (transition_delta == 3'sd0) begin
                    transition_sum <= 4'sd0;
                    left_detent    <= (ab_filtered != 2'b11);
                end
                else if (ab_filtered == 2'b11) begin
                    // Include the final transition that returns to 11.
                    if ((transition_sum + transition_delta) >= 4'sd2) begin
                        if (DIR_INVERT != 0)
                            ccw_pulse <= 1'b1;
                        else
                            cw_pulse <= 1'b1;
                    end
                    else if ((transition_sum + transition_delta) <= -4'sd2) begin
                        if (DIR_INVERT != 0)
                            cw_pulse <= 1'b1;
                        else
                            ccw_pulse <= 1'b1;
                    end

                    transition_sum <= 4'sd0;
                    left_detent    <= 1'b0;
                end
                else begin
                    transition_sum <= transition_sum + transition_delta;

                    if (ab_previous == 2'b11)
                        left_detent <= 1'b1;
                end

                ab_previous <= ab_filtered;
            end

            // Prevent a stale partial sum from surviving a reset-like idle
            // condition at the detent.
            if (!left_detent && (ab_filtered == 2'b11) &&
                (ab_previous == 2'b11))
                transition_sum <= 4'sd0;
        end
    end

endmodule



// ============================================================================
// Active-low EC11 push-key debounce and edge detector
// ============================================================================

module ch9350_debounce_event #(
    parameter integer CLK_HZ      = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer ACTIVE_LOW  = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output reg  key_level,
    output reg  press_pulse,
    output reg  release_pulse
);

    localparam integer DEBOUNCE_CYCLES_CALC =
        (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer DEBOUNCE_CYCLES =
        (DEBOUNCE_CYCLES_CALC < 1) ? 1 : DEBOUNCE_CYCLES_CALC;

    (* ASYNC_REG = "TRUE" *) reg [1:0] key_sync;
    reg raw_pressed;
    reg stable_pressed;
    reg [31:0] stable_count;

    wire sampled_pressed =
        (ACTIVE_LOW != 0) ? ~key_sync[1] : key_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            key_sync <= (ACTIVE_LOW != 0) ? 2'b11 : 2'b00;
        else
            key_sync <= {key_sync[0], key_in};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_pressed   <= 1'b0;
            stable_pressed<= 1'b0;
            stable_count  <= 32'd0;
            key_level     <= 1'b0;
            press_pulse   <= 1'b0;
            release_pulse <= 1'b0;
        end
        else begin
            press_pulse   <= 1'b0;
            release_pulse <= 1'b0;

            if (sampled_pressed != raw_pressed) begin
                raw_pressed  <= sampled_pressed;
                stable_count <= 32'd0;
            end
            else if (sampled_pressed != stable_pressed) begin
                if (stable_count >= DEBOUNCE_CYCLES - 1) begin
                    stable_count   <= 32'd0;
                    stable_pressed <= sampled_pressed;
                    key_level      <= sampled_pressed;

                    if (sampled_pressed)
                        press_pulse <= 1'b1;
                    else
                        release_pulse <= 1'b1;
                end
                else begin
                    stable_count <= stable_count + 1'b1;
                end
            end
            else begin
                stable_count <= 32'd0;
                key_level    <= stable_pressed;
            end
        end
    end

endmodule
