# PicoRV32-AXI-SoC Microarchitectural Specification

**Author:** Prakhar Chaurasia  
**Target:** AMBA AXI4-Lite Interconnect & Peripherals  

---
 
## 1. System Overview
The PicoRV32-AXI-SoC is a 32-bit System-on-Chip (SoC) based on the RISC-V RV32I instruction set architecture. It features an integrated AMBA AXI4-Lite interconnect matrix connecting the core CPU master to an 8 KB Boot ROM, a 64 KB Scratchpad SRAM, and a full-duplex memory-mapped UART controller.

---

## 2. Global Address Map

| Slave Port | Device | Base Address | Top Address | Size | Access | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `S0` | Boot ROM | `0x0000_0000` | `0x0000_FFFF` | 64 KB (8 KB active) | R | Reset vector, bootloader C runtime |
| `S1` | Data SRAM | `0x0001_0000` | `0x0001_FFFF` | 64 KB | R/W | Scratchpad data memory, stack (`sp`) |
| `S2` | UART IP | `0x1000_0000` | `0x1000_000F`   | 16 Bytes | R/W | Serial TX/RX and status registers |

---

## 3. Bus Protocol: AMBA AXI4-Lite

### 3.1 Channel Signals
The SoC implements all 5 independent AXI4-Lite channels:

1. **Write Address Channel (AW):**
   - `awaddr[31:0]`: Write target address.
   - `awvalid`: Master indicates valid write address.
   - `awready`: Slave indicates acceptance of write address.

2. **Write Data Channel (W):**
   - `wdata[31:0]`: Write data payload.
   - `wstrb[3:0]`: Byte write strobes (`1` = valid byte lane).
   - `wvalid`: Master indicates valid write data.
   - `wready`: Slave indicates acceptance of write data.

3. **Write Response Channel (B):**
   - `bresp[1:0]`: Write status (`2'b00` = `OKAY`).
   - `bvalid`: Slave indicates valid response.
   - `bready`: Master indicates response acceptance.

4. **Read Address Channel (AR):**
   - `araddr[31:0]`: Read target address.
   - `arvalid`: Master indicates valid read address.
   - `arready`: Slave indicates acceptance of read address.

5. **Read Data Channel (R):**
   - `rdata[31:0]`: Read data payload.
   - `rresp[1:0]`: Read status (`2'b00` = `OKAY`).
   - `rvalid`: Slave indicates valid read data.
   - `rready`: Master indicates data acceptance.

### 3.2 Handshake Rules
- A transfer occurs only on the rising clock edge when both `VALID` and `READY` are high.
- The master must not wait for `READY` to assert `VALID`.
- Once `VALID` is asserted, payload signals must remain stable until the handshake completes.

---

## 4. UART Peripheral Register Architecture (`0x1000_0000`)

### 4.1 Data Register (`UART_DATA`: `0x1000_0000`)
- **Write:** Bits `[7:0]` are transferred into the internal TX holding buffer. Supported by byte-lane strobes `wstrb[3:0]`.
- **Read:**
  - Bits `[7:0]`: Last received data byte from UART RX engine.
  - Bit `[8]`: `rx_buf_valid` (1 if unread byte is present).
  - Bits `[31:9]`: Reserved (tied to `0`).
  - *Side Effect:* Reading this register pops the RX buffer and deasserts `rx_buf_valid`.

### 4.2 Status Register (`UART_STATUS`: `0x1000_0008`)
- **Read-Only:**
  - Bit `[0]`: `tx_busy` (1 if transmitter is actively shifting a byte).
  - Bit `[1]`: `rx_valid` (1 if received byte is ready).
  - Bits `[31:2]`: Reserved (`0`). 
  - *Non-Destructive:* Reading this register does NOT pop or clear the RX buffer, enabling safe non-destructive polling loops.

---

## 5. Clocking and Reset Strategy
- **System Clock (`clk`):** Nominal 50.0 MHz (20.0 ns period).
- **Reset (`reset`):** Synchronous/asynchronous active-high reset. All control FSMs and buffer valid registers initialize to known zero states upon assertion.
