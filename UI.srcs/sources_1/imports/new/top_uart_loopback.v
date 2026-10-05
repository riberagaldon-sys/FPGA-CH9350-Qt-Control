module top_uart_loopback (
    input  wire UART_RXD,
    output wire UART_TXD
);

    assign UART_TXD = UART_RXD;

endmodule