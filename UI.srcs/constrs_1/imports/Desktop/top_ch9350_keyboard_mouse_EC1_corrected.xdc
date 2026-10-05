# EC1 corrected constraints for the FPGA core board
# Clock and UART
set_property PACKAGE_PIN W19 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]

set_property PACKAGE_PIN G15 [get_ports CH9350_RXD]
set_property IOSTANDARD LVCMOS33 [get_ports CH9350_RXD]
set_property PACKAGE_PIN AA14 [get_ports UART_RXD]
set_property IOSTANDARD LVCMOS33 [get_ports UART_RXD]
set_property PACKAGE_PIN V14 [get_ports UART_TXD]
set_property IOSTANDARD LVCMOS33 [get_ports UART_TXD]

# LEDs
set_property PACKAGE_PIN J16 [get_ports LED0]
set_property IOSTANDARD LVCMOS33 [get_ports LED0]
set_property PACKAGE_PIN E22 [get_ports LED1]
set_property IOSTANDARD LVCMOS33 [get_ports LED1]

# Stepper motor
set_property PACKAGE_PIN AA20 [get_ports I_SETP_MOTOR_BA]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BA]
set_property PACKAGE_PIN AA21 [get_ports I_SETP_MOTOR_BB]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BB]
set_property PACKAGE_PIN Y21 [get_ports I_SETP_MOTOR_BC]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BC]
set_property PACKAGE_PIN Y22 [get_ports I_SETP_MOTOR_BD]
set_property IOSTANDARD LVCMOS33 [get_ports I_SETP_MOTOR_BD]

# DC motor / optical feedback
set_property PACKAGE_PIN U18 [get_ports DC_MOTORA]
set_property IOSTANDARD LVCMOS33 [get_ports DC_MOTORA]
set_property PACKAGE_PIN V17 [get_ports DC_MOTOR_SPEED]
set_property IOSTANDARD LVCMOS33 [get_ports DC_MOTOR_SPEED]

# EC1 encoder
# The schematic routes EC_A to F_B14_L17_P = AA18.
# EC_B routes to F_B14_L15_P = AA19.
# EC_KEY routes to F_B14_L15_N = AB20.
set_property PACKAGE_PIN AA18 [get_ports EC_A]
set_property IOSTANDARD LVCMOS33 [get_ports EC_A]
set_property PULLUP true [get_ports EC_A]

set_property PACKAGE_PIN AA19 [get_ports EC_B]
set_property IOSTANDARD LVCMOS33 [get_ports EC_B]
set_property PULLUP true [get_ports EC_B]

set_property PACKAGE_PIN AB20 [get_ports EC_KEY]
set_property IOSTANDARD LVCMOS33 [get_ports EC_KEY]
set_property PULLUP true [get_ports EC_KEY]
