# ============================================================
# 100 MHz system clock
# ============================================================

set_property PACKAGE_PIN W19 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

create_clock -period 10.000 -name sys_clk [get_ports sys_clk]


# ============================================================
# CH9350 -> FPGA
# 当前测试不使用，但是保留
# ============================================================

set_property PACKAGE_PIN G15 [get_ports CH9350_RXD]
set_property IOSTANDARD LVCMOS33 [get_ports CH9350_RXD]


# ============================================================
# PC -> CH340E -> FPGA
# ============================================================

set_property PACKAGE_PIN AA14 [get_ports UART_RXD]
set_property IOSTANDARD LVCMOS33 [get_ports UART_RXD]


# ============================================================
# FPGA -> CH340E -> PC
# ============================================================

set_property PACKAGE_PIN V14 [get_ports UART_TXD]
set_property IOSTANDARD LVCMOS33 [get_ports UART_TXD]


# ============================================================
# LEDs
# ============================================================

set_property PACKAGE_PIN J16 [get_ports LED0]
set_property IOSTANDARD LVCMOS33 [get_ports LED0]

set_property PACKAGE_PIN E22 [get_ports LED1]
set_property IOSTANDARD LVCMOS33 [get_ports LED1]

# ============================================================
# Stepper Motor
# ============================================================

# BA -> F_B14_L8_P -> AA20
set_property PACKAGE_PIN AA20 [get_ports I_SETP_MOTOR_BA]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BA]

# BB -> F_B14_L8_N -> AA21
set_property PACKAGE_PIN AA21 [get_ports I_SETP_MOTOR_BB]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BB]

# BC -> F_B14_L9_P -> Y21
set_property PACKAGE_PIN Y21 [get_ports I_SETP_MOTOR_BC]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BC]

# BD -> F_B14_L9_N -> Y22
set_property PACKAGE_PIN Y22 [get_ports I_SETP_MOTOR_BD]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BD]

# =====================================================
# DC Motor
# BSW_CTRL1：4=ON，5=OFF，6=ON
# =====================================================

# 方向A
set_property PACKAGE_PIN U18 [get_ports DC_MOTORA]
set_property IOSTANDARD LVCMOS33 [get_ports DC_MOTORA]

# 方向B / EC_B 共用引脚
#
# EC1_HW_MODE=1，BSW_CTRL1 4/5/6=ON/ON/ON：
#   FPGA端口DC_MOTORB为高阻，AA19作为EC_B输入。
# EC1_HW_MODE=0，BSW_CTRL1 4/5/6=ON/OFF/ON：
#   AA19作为直流电机方向B输出。
set_property PACKAGE_PIN AB18 [get_ports EC_B]
set_property IOSTANDARD LVCMOS33 [get_ports EC_B]
set_property PULLUP true [get_ports EC_B]

# 光电槽型传感器反馈；每个有效脉冲表示转盘转过1/4圈。
# 这是输入信号，不是PWM输出。电机PWM仍加在当前方向的A/B桥臂上。
set_property PACKAGE_PIN V17 [get_ports DC_MOTOR_SPEED]
set_property IOSTANDARD LVCMOS33 [get_ports DC_MOTOR_SPEED]


# ============================================================
# Physical FPGA_EC1
# BSW_CTRL1：4=ON，5=ON，6=ON
# EC_B通过上面的共用端口DC_MOTORB/AA19读取
# ============================================================

set_property PACKAGE_PIN AA19 [get_ports EC_A]
set_property IOSTANDARD LVCMOS33 [get_ports EC_A]
set_property PULLUP true [get_ports EC_A]

set_property PACKAGE_PIN AB20 [get_ports EC_KEY]
set_property IOSTANDARD LVCMOS33 [get_ports EC_KEY]
set_property PULLUP true [get_ports EC_KEY]
