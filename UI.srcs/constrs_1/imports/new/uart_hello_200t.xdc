# ============================================================
# 100 MHz FPGA clock
# ============================================================

set_property PACKAGE_PIN W19 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

create_clock -period 10.000 -name sys_clk [get_ports sys_clk]


# ============================================================
# CH9350L -> FPGA
#
# CH9350 TXD
# jumper 2-3
# FPGA G15
# ============================================================

set_property PACKAGE_PIN G15 [get_ports CH9350_RXD]
set_property IOSTANDARD LVCMOS33 [get_ports CH9350_RXD]


# ============================================================
# FPGA -> CH340E -> PC
#
# FPGA UART TX = V14
# ============================================================

set_property PACKAGE_PIN V14 [get_ports UART_TXD]
set_property IOSTANDARD LVCMOS33 [get_ports UART_TXD]


# ============================================================
# LED0
# ============================================================

set_property PACKAGE_PIN J16 [get_ports LED0]
set_property IOSTANDARD LVCMOS33 [get_ports LED0]