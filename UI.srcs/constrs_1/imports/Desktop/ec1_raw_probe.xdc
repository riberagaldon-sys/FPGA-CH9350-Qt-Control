# Standalone probe: use only this XDC when ec1_raw_probe is the top.
# EC_A=AB18 matches the original constraints and the working Game(7) project.
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]
set_property -dict {PACKAGE_PIN AB18 IOSTANDARD LVCMOS33 PULLUP true} [get_ports EC_A]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports EC_B]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33 PULLUP true} [get_ports EC_KEY]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports UART_TXD]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports LED0]
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS33} [get_ports LED1]
