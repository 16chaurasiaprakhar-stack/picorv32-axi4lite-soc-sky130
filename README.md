# PicoRV32-AXI-SoC: Synthesizable 32-bit RISC-V SoC with AXI4-Lite Interconnect, UART Subsystem & Sky130 ASIC Implementation

[![RTL Verification](https://img.shields.io/badge/Verification-Icarus%20%7C%20Verilator-brightgreen.svg)](#verification--simulation-framework)
[![Architecture](https://img.shields.io/badge/Architecture-RV32IMC%20%2F%20RV32I-blue.svg)](#system-architecture)
[![Bus Protocol](https://img.shields.io/badge/Bus-AMBA%20AXI4--Lite-orange.svg)](#amba-axi4-lite-interconnect--memory-map)
[![PDK](https://img.shields.io/badge/PDK-SkyWater%20130nm-red.svg)](#asic-physical-design--openlane-flow)
[![Flow](https://img.shields.io/badge/ASIC%20Flow-OpenLane%20%7C%20Yosys-purple.svg)](#asic-physical-design--openlane-flow)

**Author:** Prakhar Chaurasia  
**Role:** Digital IC & RTL Design Engineer  
**Focus:** RISC-V Microarchitecture, AMBA Interconnects, ASIC Implementation & Verification  

---

## Table of Contents
1. [Project Motivation & Design Goals](#project-motivation--design-goals)
2. [System Architecture](#system-architecture)
3. [AMBA AXI4-Lite Interconnect & Memory Map](#amba-axi4-lite-interconnect--memory-map)
4. [Custom Hardware Subsystems & Microarchitecture](#custom-hardware-subsystems--microarchitecture)
   - [PicoRV32 Core Integration](#picorv32-core-integration)
   - [AXI4-Lite Address Decoder & Crossbar Interconnect](#axi4-lite-address-decoder--crossbar-interconnect)
   - [Full-Duplex UART Peripheral with Hardware Backpressure](#full-duplex-uart-peripheral-with-hardware-backpressure)
   - [Dual-Mode Boot ROM & 64 KB Scratchpad SRAM](#dual-mode-boot-rom--64-kb-scratchpad-sram)
5. [Hardware-Software Co-Design & Bare-Metal Firmware](#hardware-software-co-design--bare-metal-firmware)
6. [Verification & Simulation Framework](#verification--simulation-framework)
   - [Automated Test Suite Summary](#automated-test-suite-summary)
   - [Step-by-Step Simulation Reproduction](#step-by-step-simulation-reproduction)
7. [ASIC Physical Design & OpenLane Flow (SkyWater 130nm)](#asic-physical-design--openlane-flow-skywater-130nm)
8. [Directory Structure](#directory-structure)
9. [Key Engineering Challenges & Microarchitectural Solutions](#key-engineering-challenges--microarchitectural-solutions)

---

## Project Motivation & Design Goals

Embedded silicon systems require robust, clean microarchitectures that seamlessly bridge general-purpose compute cores with standardized on-chip interconnects and real-world peripherals. The primary objective of this project is to implement a **fully synthesizable, verified 32-bit RISC-V System-on-Chip (SoC)** from bare RTL to full ASIC physical tapeout readiness.

### Core Objectives
- **Standardized Interconnect Implementation:** Bridge a pipelined RISC-V CPU core to multiple slave peripherals using an industry-standard **AMBA AXI4-Lite** interface.
- **Hardware Backpressure & Bus Deadlock Prevention:** Solve the classic peripheral rate-mismatch problem between high-speed CPU bus transactions and low-speed serial transmission through hardware flow control.
- **Hardware-Software Co-Design:** Develop a cycle-accurate bare-metal C runtime and assembly bootloader that initializes the stack, boots from internal ROM, executes memory-mapped UART transactions, and manages bidirectional serial I/O.
- **Silicon-Grade ASIC Flow:** Target the **SkyWater 130nm CMOS process (`sky130_fd_sc_hd`)** using OpenLane to achieve clean Static Timing Analysis (STA), Clock Tree Synthesis (CTS), DRC, LVS, and antenna compliance.

---

## System Architecture

The SoC integrates a 32-bit RISC-V core (`PicoRV32`) acting as an AXI4-Lite master, communicating through a non-blocking AXI4-Lite interconnect crossbar with three slave modules: an 8 KB Boot ROM, a 64 KB scratchpad SRAM, and a full-duplex memory-mapped UART controller.

```
+===================================================================================+
|                                    PicoRV32 CPU Core                              |
|                           (RV32I / RV32IMC RISC-V Architecture)                   |
|                        - Pipelined execution with AXI-Lite Master                 |
+===================================================================================+
                                         │
                   AXI4-Lite Master Interface (AW, W, B, AR, R)
                                         ▼
+===================================================================================+
|                           AXI4-Lite Interconnect Matrix                           |
|                    - 1 Master × 3 Slaves Combinational Decoder                    |
|                    - Independent Read & Write Channel Multiplexing                |
|                    - Byte-Lane Write Strobe Routing (WSTRB[3:0])                  |
|                    - Valid/Ready Handshake Forwarding & Isolation                 |
+===================================================================================+
         │                                    │                               │
         │ [0x0000_0000 - 0x0000_FFFF]        │ [0x0001_0000 - 0x0001_FFFF]   │ [0x1000_0000 - 0x1000_000F]
         ▼                                    ▼                               ▼
+-----------------------+            +-----------------------+       +-----------------------+
|      Slave 0: ROM     |            |     Slave 1: SRAM     |       |    Slave 2: UART IP   |
| - 8 KB Boot Memory    |            | - 64 KB Scratchpad    |       | - 115200 Baud @ 50MHz |
| - Synthesizable Case  |            | - Single-Cycle Access |       | - Hardware Flow Ctrl  |
|   + HEX Init Modes    |            | - Byte-Lane Masking   |       | - RX Oversampling FSM |
+-----------------------+            +-----------------------+       +-----------------------+
                                                                                 │
                                                                       tx_out ───┴─── uart_rx
```

---

## AMBA AXI4-Lite Interconnect & Memory Map

The SoC utilizes a 32-bit address and data bus conforming to ARM's AMBA AXI4-Lite specification. The interconnect decouples write address (`AW`), write data (`W`), write response (`B`), read address (`AR`), and read data (`R`) channels into independent concurrent handshakes.

### Global Address Space

| Region | Base Address | Top Address | Size | Access Type | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Boot ROM** | `0x0000_0000` | `0x0000_FFFF` | 64 KB (8 KB populated) | Read-Only | Power-on reset vector, bootloader assembly, string tables |
| **Data SRAM** | `0x0001_0000` | `0x0001_FFFF` | 64 KB | Read / Write | Application stack, global variables, scratchpad memory |
| **UART Subsystem** | `0x1000_0000` | `0x1000_000F` | 16 Bytes | Read / Write | Memory-mapped serial transmission, reception, and status |

### UART Peripheral Register Map (`0x1000_0000`)

| Offset | Register Name | Access | Field Definitions | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | `UART_DATA` | R/W | **[7:0] Data Byte**<br>**[8] `rx_buf_valid`** (Read)<br>**[31:9] Reserved** | **Write:** Queues a byte for serial transmission.<br>**Read:** Returns received byte and automatically clears the RX ready flag. |
| `0x04` | `UART_RX` | R | **[7:0] Received Byte** | Mirror read register for direct character polling. |
| `0x08` | `UART_STATUS` | R | **[0] TX Busy**<br>**[1] RX Buffer Valid**<br>**[31:2] Reserved** | Status register. Allows polling without popping the received byte. |

---

## Custom Hardware Subsystems & Microarchitecture

### PicoRV32 Core Integration
The core is integrated as an AMBA AXI4-Lite master:
- **Configurable ISA:** Configured for RV32I integer execution with hardware multiplier (`RV32M`) and compressed instruction (`RV32C`) compatibility.
- **Trap Handling:** Hardware trap detection connected to top-level monitoring for invalid memory access and unaligned instructions.
- **Bus Interface:** Converts native CPU memory requests into distinct AXI-Lite read and write channel transactions.

### AXI4-Lite Address Decoder & Crossbar Interconnect
Implemented across [`rtl/axi_decoder.v`](rtl/axi_decoder.v) and [`rtl/axi_lite_interconnect.v`](rtl/axi_lite_interconnect.v):
- **Combinational Address Decoding:** Decode logic checks `awaddr[31:16]` and `araddr[31:16]` in parallel to generate one-hot select signals (`3'b001` for ROM, `3'b010` for SRAM, `3'b100` for UART).
- **Independent Write/Read Channels:** Read and write transactions operate concurrently without mutual pipeline stalls.
- **Byte Strobe Support:** Propagates `wstrb[3:0]` down to memory and peripheral targets, enabling granular byte (`sb`), half-word (`sh`), and full-word (`sw`) operations.

### Full-Duplex UART Peripheral with Hardware Backpressure
Implemented in [`rtl/uart_axi.v`](rtl/uart_axi.v), [`rtl/uart_tx.v`](rtl/uart_tx.v), and [`rtl/uart_rx.v`](rtl/uart_rx.v):
- **Hardware Backpressure:** In conventional UART designs, CPU writes to a busy TX buffer are either silently dropped or overwrite pending data. In this design, `s_axi_awready` and `s_axi_wready` are held low whenever an active byte is being serialized and the holding buffer is full. This forces the CPU bus master to wait gracefully without losing data or hanging the bus.
- **Robust RX Sampling:** Features a mid-bit sampling engine that oversamples incoming asynchronous serial lines to prevent edge jitter and ensure high noise immunity at 115,200 baud.
- **ASIC Cleanliness:** Zero latch inference, strict non-blocking register updates, explicit active-high reset, and decoupled port naming to avoid Yosys hierarchy collisions.

### Dual-Mode Boot ROM & 64 KB Scratchpad SRAM
- **Dual-Mode Boot ROM ([`rtl/rom.v`](rtl/rom.v)):** Supports both pure combinational synthesis (via an unrolled case statement structure for standard cell ASIC synthesis) and memory-file initialization (via `$readmemh("rom.hex")` for behavioral simulation).
- **Single-Cycle SRAM ([`rtl/sram.v`](rtl/sram.v)):** 16,384 entries × 32-bit memory array with individual byte-lane write strobe handling.

---

## Hardware-Software Co-Design & Bare-Metal Firmware

The SoC includes a bare-metal C runtime and startup sequence located in [`fw/`](fw/):

1. **Reset Sequence ([`fw/start.s`](fw/start.s)):**
   - Sets up the stack pointer (`sp = 0x0001FFF0`) inside scratchpad SRAM.
   - Clears `.bss` section memory.
   - Jumps to C entry point `main()`.
2. **C Runtime Execution ([`fw/main.c`](fw/main.c)):**
   - Declares `volatile` memory-mapped I/O pointers to UART hardware registers.
   - Outputs the greeting string:
     ```
     "Hello Prakhar Chaurasia!\n"
     ```
   - Enters a polling echo loop: continuously samples `UART_STATUS` for received bytes and echoes them back over `UART_TX`.
3. **Linker Script ([`fw/linker.ld`](fw/linker.ld)):**
   - Maps `.text` and `.rodata` directly to ROM at `0x00000000`.
   - Maps `.data` and `.bss` to SRAM at `0x00010000`.

---

## Verification & Simulation Framework

The design includes a multi-tiered verification suite testing standalone IP blocks, AXI protocol compliance, bus backpressure, and full-system firmware execution.

### Automated Test Suite Summary

```
================================================================================
Test Target             Type           Verification Scope               Status
================================================================================
tb_uart_top             Unit TB        8N1 Serial Framing & Loopback    PASSED ✓
tb_axi_lite             Protocol TB    17 AXI4-Lite Handshake Tests     PASSED ✓
tb_riscv_axi_lite       Integration TB CPU-to-Interconnect Bus Bridge   PASSED ✓
tb_top / tb_debug       System TB      Full-Chip ROM Boot & Firmware    PASSED ✓
================================================================================
```

#### Detailed Breakdown of the 17 AXI4-Lite Protocol Tests:
- **T1:** Basic single-word write & response validation (`BRESP == OKAY`).
- **T2:** Single-word read from peripheral (`RRESP == OKAY`).
- **T3:** Back-to-back writes verifying zero pipeline bubble insertion.
- **T4:** Back-to-back reads validating read data path synchronization.
- **T5:** Consecutive write-after-read hazards.
- **T6:** Read address offset decoding (`0x0` data vs `0x8` status).
- **T7:** Byte-lane strobe selection (`wstrb = 0001, 0010, 0100, 1000`) for selective byte masking.

### Step-by-Step Simulation Reproduction

#### Method 1: Using the Automated Windows Script (Icarus Verilog)
```cmd
cd C:\Users\prakh\Project\picorv32-axi-soc
scripts\run_sim_all.bat
```

#### Method 2: Standalone Icarus Verilog Execution
```bash
# 1. Run UART Loopback Test
iverilog -g2012 -o uart_sim.vvp rtl/uart_top.v rtl/uart_tx.v rtl/uart_rx.v tb/tb_uart_top.v
vvp uart_sim.vvp

# 2. Run Comprehensive AXI-Lite 17-Test Suite
iverilog -g2012 -o axi_sim.vvp rtl/uart_axi.v rtl/uart_tx.v rtl/uart_rx.v tb/tb_axi_lite.v
vvp axi_sim.vvp

# 3. Run RISC-V to AXI Integration Test
iverilog -g2012 -o riscv_axi_sim.vvp rtl/top.v rtl/picorv32.v rtl/uart_axi.v rtl/uart_tx.v rtl/uart_rx.v rtl/axi_lite_interconnect.v rtl/axi_decoder.v rtl/sram.v rtl/rom.v tb/tb_riscv_axi_lite.v
vvp riscv_axi_sim.vvp
```

#### Method 3: Using Makefile (Linux / WSL / Verilator)
```bash
make uart        # Run UART loopback simulation
make axi_uart    # Run AXI-Lite protocol verification
make riscv_axi   # Run RISC-V AXI handshake integration test
make soc         # Run full-chip SoC boot simulation
make all         # Run entire simulation suite sequentially
```

---

## ASIC Physical Design & OpenLane Flow (SkyWater 130nm)

The SoC is configured for automated physical design targeting the open-source **SkyWater 130nm High-Density Standard Cell Library (`sky130_fd_sc_hd`)**.

### Physical Design Parameters ([`openlane/config.json`](openlane/config.json))

| Parameter | Value | Design Rationale |
| :--- | :--- | :--- |
| **Clock Frequency** | 50 MHz (`CLOCK_PERIOD: 20 ns`) | Conservative frequency ensuring zero setup/hold violations across PVT corners |
| **Die Area** | `1000 × 1000 µm` (1.0 mm²) | Ample silicon real estate to accommodate on-chip memory arrays and routing channels |
| **Core Utilization** | 35% (`FP_CORE_UTIL: 35`) | Low routing congestion margin for detailed routing (`met1` to `met4`) |
| **Clock Tree Skew** | < 150 ps (`CTS_TARGET_SKEW: 150`) | Low-jitter clock delivery using `sky130_fd_sc_hd__clkbuf_16` buffers |
| **Power Distribution** | Met4 / Met5 vertical & horizontal | 25 µm pitch grid with 5 µm offset for stable VDD/GND IR drop profile |
| **Antenna Protection** | Heuristic diode insertion (`MODE: 3`) | Protects thin gate oxides from plasma charge damage during metal etch |

### Post-Layout Signoff Results & Verification Metrics

| Metric | Result | Target / Limit | Status |
| :--- | :--- | :--- | :--- |
| **PDK Process** | SkyWater 130nm (`sky130_fd_sc_hd`) | 130nm CMOS | ✅ Verified |
| **Flow Status** | `flow completed` | Automated signoff flow | ✅ Passed (48m 29s) |
| **Magic DRC Violations** | **0** | 0 violations | ✅ **100% Clean** |
| **LVS Verification** | **26,364 / 26,364 nets matched** | Full netlist match | ✅ **Clean LVS** |
| **Setup Timing Slack (Worst)** | **+13.72 ns** | $\ge 0\text{ ns}$ | ✅ Timing Closed |
| **Hold Timing Slack (Worst)** | **+0.68 ns** | $\ge 0\text{ ns}$ | ✅ Timing Closed |
| **Worst Negative Slack (WNS)** | **0.00 ns** | 0.00 ns | ✅ Zero Slack |
| **Total Negative Slack (TNS)** | **0.00 ns** | 0.00 ns | ✅ Zero Slack |
| **Operating Frequency** | **50.0 MHz** ($T_{\text{clk}} = 20.0\text{ ns}$) | 50.0 MHz | ✅ Achieved |
| **Critical Path Delay** | **2.03 ns** | $< 20.0\text{ ns}$ | ✅ Timing Met |
| **Die Area** | $1.00\text{ mm}^2$ ($1000\,\mu\text{m} \times 1000\,\mu\text{m}$) | $1.0\text{ mm}^2$ | ✅ Verified |
| **Core Area** | $0.965\text{ mm}^2$ ($965,289.5\times 10^{-6}\text{ mm}^2$) | - | ✅ Verified |
| **Standard Cell Count** | **26,359 logic cells** (134,648 total incl. fill/decap) | - | ✅ Verified |
| **Total Wirelength** | $1,033,926\,\mu\text{m}$ (~1.03 m, 213,722 vias) | - | ✅ Fully Routed |
| **Total Power (Typical)** | **37.3 mW** (55.1% Internal, 44.9% Switching) | - | ✅ Low Power |

### Running Physical Synthesis & Layout
```bash
# Launch OpenLane flow in Docker container
cd openlane
flow.tcl -design .
```

---

## Directory Structure

```
picorv32-axi-soc/
├── gds/                           # Final tapeout mask layout
│   └── top.gds                    # Golden GDSII stream file (SkyWater 130nm)
├── def/                           # Physical design placement & routing
│   └── top.def                    # Complete routed DEF layout
├── reports/                       # Physical signoff & verification reports
│   ├── metrics.csv                # Complete flow metrics database
│   ├── manufacturability.rpt      # Final DRC & LVS signoff verification
│   ├── timing_summary.rpt         # Post-routing STA slack & timing report
│   ├── power_summary.rpt          # Dynamic and leakage power analysis
│   ├── clock_skew.rpt             # CTS clock skew analysis
│   └── openlane.log               # Complete automated flow execution log
├── rtl/                           # Synthesizable RTL source files
│   ├── top.v                      # SoC top-level module (CPU + Interconnect + Peripherals)
│   ├── picorv32.v                 # PicoRV32 RISC-V CPU core
│   ├── axi_lite_interconnect.v    # 1-Master to 3-Slave AXI4-Lite crossbar
│   ├── axi_decoder.v              # Combinational address decoder
│   ├── uart_axi.v                 # AXI4-Lite memory-mapped UART wrapper
│   ├── uart_tx.v                  # 8N1 UART transmitter with baud generator
│   ├── uart_rx.v                  # 8N1 UART oversampled receiver
│   ├── uart_top.v                 # Standalone loopback test wrapper
│   ├── sram.v                     # 64 KB single-cycle synchronous SRAM
│   ├── rom.v                      # 8 KB dual-mode Boot ROM
│   └── rom.hex                    # Pre-compiled bootloader binary image
├── src/                           # Local RTL copies for OpenLane environment
├── tb/                            # Verification testbenches
│   ├── tb_top.v                   # Full-chip system-level testbench
│   ├── tb_debug.v                 # System-level testbench with structured verification logging
│   ├── tb_axi_lite.v              # 17-test AXI4-Lite protocol verification suite
│   ├── tb_axi_lite_standalone.v   # Self-contained AXI-Lite bus testbench
│   ├── tb_riscv_axi_lite.v        # CPU-to-AXI handshake integration testbench
│   └── tb_uart_top.v              # UART hardware loopback testbench
├── fw/                            # Bare-metal firmware and runtime
│   ├── main.c                     # Firmware source (UART greeting banner & echo loop)
│   ├── start.s                    # RISC-V startup assembly & stack pointer initialization
│   └── linker.ld                  # Bare-metal linker script (ROM / SRAM mapping)
├── openlane/                      # SkyWater 130nm ASIC physical design
│   ├── config.json                # OpenLane synthesis & PnR configuration
│   ├── pin_order.cfg              # Chip IO pin placement constraints
│   ├── top.sdc                    # Synopsys Design Constraints (50 MHz clock definition)
│   └── src/                       # Local RTL sources
├── scripts/                       # Automation scripts
│   ├── run_sim_all.bat            # Automated Windows simulation regression script
│   └── run_commands.txt           # Detailed command guide for Verilator, Icarus & Yosys
├── Makefile                       # Unified build and simulation makefile
├── config.json                    # Root OpenLane configuration
├── pin_order.cfg                  # Root pin order configuration
├── top.sdc                        # Root timing constraints
├── LICENSE                        # MIT License
└── .gitignore                     # Git ignore rules for build artifacts and scratch folders
```

---

## Key Engineering Challenges & Microarchitectural Solutions

### 1. AXI4-Lite Backpressure & Buffer Overrun Prevention
- **The Issue:** Standard microcontrollers running at 50 MHz issue memory-mapped UART writes in single-cycle bursts. Because UART serialization at 115,200 baud requires ~434 clock cycles per bit (4,340 cycles per character), the CPU rapidly overruns the peripheral if no flow control exists.
- **The Solution:** Implemented an internal holding buffer paired with strict write handshake qualification. If `buf_valid` is asserted, both `s_axi_awready` and `s_axi_wready` are driven low, enforcing hardware bus backpressure. The CPU stalls until the current byte has transferred into the shift register, ensuring 100% data integrity without dropped characters.

### 2. Yosys Scoping & Port/Type Name Collision
- **The Issue:** In synthesis tools such as Yosys, giving a port the same identifier as a instantiated submodule type (e.g., `output uart_tx` inside `uart_axi` instantiating `uart_tx u_tx (...)`) can cause scope-resolution ambiguity. During netlist flattening, the optimizer can misidentify the wire driver and disconnect the output port.
- **The Solution:** Renamed internal connection ports to `tx_out` and mapped them cleanly at the top-level boundary, ensuring deterministic elaboration across both Yosys and commercial ASIC synthesizers.

### 3. Dual-Mode Boot ROM Architecture
- **The Issue:** Behavioral `$readmemh` memory initialization is ideal for fast cycle-accurate simulation in Icarus/Verilator, but standard cell ASIC flows without SRAM compilers require combinational standard cell gates or read-only macro blocks.
- **The Solution:** Structured [`rtl/rom.v`](rtl/rom.v) with conditional synthesis defines (`SYNTHESIS`), falling back to an unrolled 2048-word `case` statement that synthesizes directly into a combinational cell ROM during OpenLane layout while retaining `$readmemh` for fast testbench turnaround.

---

## License

This project is licensed under the MIT License — feel free to use and adapt it for academic research, open-source silicon projects, or ASIC design portfolios.
