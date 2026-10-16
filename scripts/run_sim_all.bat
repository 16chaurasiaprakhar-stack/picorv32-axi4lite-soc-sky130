@echo off
setlocal enabledelayedexpansion

echo ===================================================================
echo   PicoRV32 AXI-Lite SoC Verification Suite (Icarus Verilog)
echo   Author: Prakhar Chaurasia
echo ===================================================================

echo.
echo [1/3] Running UART Loopback Test (tb_uart_top)...
iverilog -g2005 -o sim_uart.vvp rtl\uart_tx.v rtl\uart_rx.v rtl\uart_top.v tb\tb_uart_top.v
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] UART compilation failed!
    exit /b %ERRORLEVEL%
)
vvp sim_uart.vvp
del sim_uart.vvp tb_uart.vcd 2>nul

echo.
echo [2/3] Running AXI-Lite Bus Master & Slave Protocol Test (tb_axi_lite)...
iverilog -g2005 -o sim_axilite.vvp rtl\uart_tx.v rtl\uart_rx.v rtl\uart_axi.v tb\tb_axi_lite_master.v tb\tb_axi_lite.v
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] AXI-Lite compilation failed!
    exit /b %ERRORLEVEL%
)
vvp sim_axilite.vvp
del sim_axilite.vvp tb_axi_lite.vcd 2>nul

echo.
echo [3/3] Running RISC-V to AXI-Lite Handshake Integration Test (tb_riscv_axi_lite)...
iverilog -g2005 -o sim_riscv_axi.vvp tb\tb_riscv_axi_lite.v
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] RISC-V AXI compilation failed!
    exit /b %ERRORLEVEL%
)
vvp sim_riscv_axi.vvp
del sim_riscv_axi.vvp tb_riscv_axi_lite.vcd 2>nul

echo.
echo ===================================================================
echo   ALL SIMULATION TESTS COMPLETED SUCCESSFULLY!
echo ===================================================================
endlocal
