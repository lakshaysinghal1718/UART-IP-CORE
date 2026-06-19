# UART IP Core — Phase 2: Synchronous FIFOs with Overrun Detection

![Language](https://img.shields.io/badge/Language-Verilog-blue)
![Status](https://img.shields.io/badge/Status-Verified%20%26%20Passing-brightgreen)
![Phase](https://img.shields.io/badge/Phase-2%20of%205-orange)
![Simulator](https://img.shields.io/badge/Simulator-Vivado%202025.2-purple)

A fully parameterized, verified UART IP Core with synchronous TX and RX FIFOs, hardware overrun detection, and a self-checking testbench covering burst writes, golden reference comparison, and overrun error assertion. This is Phase 2 of a 5-phase project culminating in a full APB-wrapped UART with fractional baud rate generation, hardware flow control, and SystemVerilog constrained-random verification.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Module Hierarchy](#module-hierarchy)
- [Parameters](#parameters)
- [Port Descriptions](#port-descriptions)
- [Design Decisions](#design-decisions)
- [Baud Rate Generation](#baud-rate-generation)
- [Transmitter FSM](#transmitter-fsm)
- [Receiver FSM](#receiver-fsm)
- [Parity Logic](#parity-logic)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Testbench and Verification](#testbench-and-verification)
- [Simulation Results](#simulation-results)
- [Toolchain](#toolchain)
- [Roadmap](#roadmap)

---

## Overview

Phase 2 integrates parameterized synchronous FIFOs into both the TX and RX paths of the UART core, eliminating the need for per-byte CPU polling and enabling burst transfers. The CPU writes multiple bytes into the TX FIFO without waiting for each transmission to complete. Received bytes accumulate in the RX FIFO until the CPU drains them. Hardware overrun detection flags any byte that arrives when the RX FIFO is already full.

The TX FIFO feeds the transmitter autonomously — `tx_start_internal` fires whenever the FIFO is non-empty and the transmitter is idle, with no CPU involvement after the initial write burst. The RX FIFO is written directly from `rx_valid`, keeping the data path from receiver to memory purely hardware-driven.

Phase 2 delivers five RTL modules and one self-checking testbench:

| Module | Function |
|---|---|
| `baud_gen.v` | Free-running baud tick and oversample tick generator |
| `uart_tx.v` | UART transmitter FSM with parameterized parity and stop bits |
| `uart_rx.v` | UART receiver FSM with 16x oversampling and double-flop sync |
| `fifo.v` | Parameterized synchronous FIFO with full/empty flags and programmable thresholds |
| `uart_top.v` | Top-level integration: TX FIFO → TX, RX → RX FIFO, overrun detection |
| `tb_uart_top.v` | Self-checking testbench: burst write/drain with golden reference, overrun detection |

---

## Architecture

```
                         ┌──────────────────────────────────────────────────────────┐
                         │                        uart_top                           │
                         │                                                           │
  clk   ────────────────►│─► baud_gen ──► baud_tick  ──────────────► uart_tx        │
  rst_n ────────────────►│        │                                      │           │
                         │        └──► sample_tick ──────► uart_rx       │ tx_out   │──► tx_out
  tx_wr_en ────────────►│                                    │           │           │
  tx_data_in ──────────►│──► TX FIFO ──► tx_fifo_dout ──────┼──► TX  ──►│           │
                         │       │                           │           │           │
  tx_fifo_full ◄────────│◄──────┤                       rx_valid        │           │
  tx_fifo_empty ◄───────│◄──────┘                           │           │           │
                         │                                   ▼           │           │
  rx_rd_en ────────────►│                              RX FIFO ◄────────┘           │
  rx_data_out ◄─────────│◄───────────────────────────────── │                       │
  rx_fifo_full ◄────────│◄──────────────────────────────────┤                       │
  rx_fifo_empty ◄───────│◄──────────────────────────────────┘                       │
  overrun_err ◄─────────│◄── (rx_valid && rx_fifo_full)                             │
                         │                                                           │
  rx_in ───────────────►│─────────────────────────────────────────────► uart_rx     │
                         └──────────────────────────────────────────────────────────┘
```

The TX FIFO read and the transmitter start signal are the same wire — `tx_start_internal = !tx_fifo_empty && !tx_busy`. This means the FIFO drains into the transmitter continuously without any software intervention after the initial burst write.

`overrun_err` is a combinational signal: `assign overrun_err = rx_valid && rx_fifo_full`. It pulses for exactly one clock cycle each time a byte arrives at an already-full RX FIFO.

---

## Module Hierarchy

```
uart_top
├── baud_gen        (u_baud_gen)
├── fifo            (u_tx_fifo)
├── uart_tx         (u_uart_tx)
├── uart_rx         (u_uart_rx)
└── fifo            (u_rx_fifo)
```

---

## Parameters

All parameters are elaboration-time constants propagated from `uart_top` down to submodules. `defparam` is not used anywhere; all overrides use `#(.PARAM(value))` instantiation syntax.

| Parameter | Default | Applies To | Description |
|---|---|---|---|
| `DATA_BITS` | `8` | uart_top, uart_tx, uart_rx, fifo | Serial frame data width. Valid range: 5–9 bits. |
| `PARITY_TYPE` | `0` | uart_top, uart_tx, uart_rx | `0` = None, `1` = Even, `2` = Odd |
| `STOP_BITS` | `1` | uart_top, uart_tx, uart_rx | `1` = one stop bit, `2` = two stop bits |
| `ADDR_WIDTH` | `4` | uart_top, fifo | FIFO address width. Depth = `1 << ADDR_WIDTH`. Default: 16 entries. |
| `N` | `434` | baud_gen | TX baud counter period. For 50 MHz / 115200 baud: ⌊50,000,000 / 115,200⌋ = 434 |
| `N_rx` | `27` | baud_gen | RX oversample counter period. For 16x oversampling: ⌊434 / 16⌋ = 27 |

Counter widths inside `baud_gen` are derived automatically via `$clog2(N)` and `$clog2(N_rx)`, making the module fully parameterized without manual width calculations. FIFO depth is always a power of two — pointer wraparound is implicit in the `ADDR_WIDTH`-bit counters.

---

## Port Descriptions

### uart_top

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | input | 1 | System clock. All logic is synchronous to rising edge. |
| `rst_n` | input | 1 | Active-low synchronous reset. |
| `tx_wr_en` | input | 1 | Assert for one clock cycle to write one byte into the TX FIFO. |
| `tx_data_in` | input | DATA_BITS | Data byte to load into TX FIFO. Must be stable while `tx_wr_en` is asserted. |
| `tx_fifo_full` | output | 1 | TX FIFO is full. CPU must not assert `tx_wr_en` while this is high. |
| `tx_fifo_empty` | output | 1 | TX FIFO is empty. Transmitter is idle when this is high and `tx_busy` is low. |
| `rx_rd_en` | input | 1 | Assert for one clock cycle to read one byte from the RX FIFO. |
| `rx_data_out` | output | DATA_BITS | Data byte read from RX FIFO. Valid on the cycle `rx_rd_en` is asserted and `rx_fifo_empty` is low. |
| `rx_fifo_full` | output | 1 | RX FIFO is full. Next received byte will assert `overrun_err`. |
| `rx_fifo_empty` | output | 1 | RX FIFO is empty. CPU must not assert `rx_rd_en` while this is high. |
| `tx_out` | output | 1 | UART serial transmit line. Idles high. |
| `rx_in` | input | 1 | UART serial receive line. |
| `overrun_err` | output | 1 | Combinational pulse: asserts when `rx_valid` and `rx_fifo_full` coincide. Lost byte. |

### fifo

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low synchronous reset. Clears pointers and count. |
| `wr_en` | input | 1 | Write enable. Ignored when `full` is high. |
| `rd_en` | input | 1 | Read enable. Ignored when `empty` is high. |
| `din` | input | DATA_WIDTH | Data to write. |
| `full_threshold` | input | ADDR_WIDTH+1 | `almost_full` asserts when `data_count >= full_threshold`. |
| `empty_threshold` | input | ADDR_WIDTH+1 | `almost_empty` asserts when `data_count <= empty_threshold`. |
| `dout` | output | DATA_WIDTH | Combinational read: `assign dout = mem[read_ptr]`. No read latency. |
| `full` | output | 1 | FIFO is full (`data_count == 1 << ADDR_WIDTH`). |
| `empty` | output | 1 | FIFO is empty (`data_count == 0`). |
| `almost_full` | output | 1 | `data_count >= full_threshold`. |
| `almost_empty` | output | 1 | `data_count <= empty_threshold`. |
| `data_count` | output | ADDR_WIDTH+1 | Current number of entries in the FIFO. |

### baud_gen

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low synchronous reset |
| `baud_tick` | output | 1 | One-cycle pulse at TX baud rate (115200 Hz at 50 MHz) |
| `sample_tick` | output | 1 | One-cycle pulse at 16× baud rate for RX oversampling |

---

## Design Decisions

**Combinational FIFO read output.** `dout` is driven as `assign dout = mem[read_ptr]` rather than a registered read. This eliminates one cycle of read latency on the TX path — when `tx_start_internal` fires, `tx_fifo_dout` is already valid and the transmitter captures the correct byte immediately. A registered read would require an extra cycle of pipeline delay between FIFO drain and TX load.

**tx_start_internal as a combinational wire.** `wire tx_start_internal = (!tx_fifo_empty) && (!tx_busy)` means the transmitter starts autonomously the moment the FIFO has data and the TX core is idle. The TX FIFO read enable is the same signal — no separate handshake state machine needed.

**overrun_err as a combinational assign.** `assign overrun_err = rx_valid && rx_fifo_full` produces a one-cycle pulse that is architecturally tied to the exact cycle a byte is lost. A registered version would add one cycle of latency to the error flag and complicate the timing relationship between the lost byte and the flag. The combinational version is the correct choice here.

**data_count as the full/empty source of truth.** `full` and `empty` are derived combinationally from `data_count` rather than from pointer comparison. This avoids the MSB XOR trick and makes the logic explicit and readable at the cost of one extra adder bit. For a 16-deep FIFO this is not a synthesis concern.

**Synchronous active-low reset throughout.** Consistent with Phase 1. All flip-flops reset on the same clock edge, avoiding reset-domain skew.

**Programmable thresholds tied off for Phase 2.** `full_threshold` and `empty_threshold` are wired to `{ADDR_WIDTH+1{1'b1}}` and `0` respectively in `uart_top`. The `almost_full` and `almost_empty` outputs are left unconnected. These will be mapped to interrupt logic in Phase 4 when the APB register map is added.

---

## Baud Rate Generation

For a 50 MHz system clock and 115200 baud target:

```
TX counter period N     = floor(50,000,000 / 115,200)    = 434 cycles
Actual TX baud rate     = 50,000,000 / 434               = 115,207 baud
Baud rate error         = (115,207 - 115,200) / 115,200  = 0.006%

RX oversample period    = floor(434 / 16)                = 27 cycles
Actual sample rate      = 50,000,000 / 27                = 1,851,851 Hz
Oversample ratio        = 1,851,851 / 115,207            ≈ 16.07x
```

A baud rate error below 2% is the industry standard tolerance for UART receivers. At 0.006%, this design has substantial margin. The 16x oversampling means center sampling occurs at sample 8 of 16, providing ±7 samples of jitter tolerance before a bit is missampled.

---

## Transmitter FSM

The TX FSM has six states. State transitions are gated on `baud_tick` except the IDLE→START arc which is gated on `tx_start`.

```
TX_IDLE ──(tx_start)──► TX_START ──(baud_tick)──► TX_DATA
                                                      │
                              ┌───(all bits sent, PARITY_TYPE!=0)──► TX_PARITY
                              │                                           │
                              └───(all bits sent, PARITY_TYPE==0)────────┤
                                                                          ▼
                                                                       TX_STOP
                                                                          │
                              ┌───(STOP_BITS==2)──► TX_STOP2 ────────────┤
                              │                         │                 │
                              └─────────────────────────┴──(baud_tick)──► TX_IDLE
                                                          (tx_done pulse)
```

Key output behavior:
- `tx_out` idles HIGH (mark state). Start bit is LOW. Stop bits are HIGH.
- `tx_done` is a registered one-cycle pulse, asserted in TX_STOP or TX_STOP2 on the `baud_tick` that ends the stop bit, cleared immediately on entry to TX_IDLE.
- `tx_busy` is a combinational wire: `assign tx_busy = (state != TX_IDLE)`.

---

## Receiver FSM

The RX FSM has six states. All state transitions are gated on `sample_tick`. Center sampling occurs at `oversample_cnt == 7` — the 8th sample_tick after entering each state, which corresponds to the center of each bit period.

```
RX_IDLE ──(rx_sync2==0)──► RX_START
                               │
                    (oversample_cnt==7, rx_sync2==0)
                               │
                               ▼
                            RX_DATA ──(all bits received, PARITY_TYPE!=0)──► RX_PARITY
                               │                                                  │
                               └──(all bits received, PARITY_TYPE==0)────────────┤
                                                                                  ▼
                                                                               RX_STOP
                                                                                  │
                              ┌───(STOP_BITS==2, rx_sync2==1)──► RX_STOP2 ───────┤
                              │                                       │            │
                              └───────────────────────────────────────┴──► RX_IDLE
```

Key output behavior:
- `rx_valid` asserts for one clock cycle in RX_STOP (1 stop bit) or RX_STOP2 (2 stop bits) only when `rx_sync2 == 1` (valid stop bit).
- `frame_err` asserts when `rx_sync2 == 0` during stop bit sampling.
- `rx_data` is latched from `shift_reg` at the same cycle `rx_valid` asserts.
- Data is assembled LSB-first: `shift_reg <= {rx_sync2, shift_reg[DATA_BITS-1:1]}`.

---

## Parity Logic

Parity is computed incrementally as each data bit is shifted out (TX) or sampled (RX) using a running XOR accumulator `parity_reg`, initialized to 0 at the start of each frame.

```
parity_reg[n] = parity_reg[n-1] ^ current_bit
```

After all DATA_BITS have been processed, `parity_reg` holds the even parity of the entire data word.

| PARITY_TYPE | TX sends | RX expects |
|---|---|---|
| 0 (None) | TX_PARITY state skipped | RX_PARITY state skipped |
| 1 (Even) | `parity_reg` | `rx_sync2 == parity_reg` |
| 2 (Odd) | `~parity_reg` | `rx_sync2 == ~parity_reg` |

If the received parity bit does not match the expected value, `parity_err` asserts and remains high until the FSM returns to RX_IDLE.

---

## Project Structure

```
uart-ip-core/
├── rtl/
│   ├── baud_gen.v          Free-running baud tick and oversample tick generator
│   ├── uart_tx.v           UART transmitter FSM
│   ├── uart_rx.v           UART receiver FSM with 16x oversampling
│   ├── fifo.v              Parameterized synchronous FIFO
│   └── uart_top.v          Top-level integration with TX/RX FIFOs
├── tb/
│   └── tb_uart_top.v       Self-checking testbench: burst transfer + overrun detection
├── docs/
│   └── waveforms/
│       └── (waveform screenshots)
├── .gitignore
└── README.md
```

---

## Getting Started

### Prerequisites

- Vivado 2025.2 (simulation used for verification)
- OR: Icarus Verilog 11+ with GTKWave for open-source simulation

### Simulation — Vivado

1. Clone the repository:
```bash
git clone https://github.com/lakshaysinghal1718/UART-IP-CORE
cd UART-IP-CORE
```

2. Open Vivado, create a new project, add all files under `rtl/` as design sources and `tb/tb_uart_top.v` as a simulation source.

3. Set `tb_uart_top` as the simulation top module.

4. Run Behavioral Simulation. The testbench runs all test sequences and calls `$finish` automatically.

### Simulation — Icarus Verilog

```bash
iverilog -o uart_sim rtl/baud_gen.v rtl/uart_tx.v rtl/uart_rx.v rtl/fifo.v rtl/uart_top.v tb/tb_uart_top.v
vvp uart_sim
```

### Changing Parameters

Override at instantiation in `uart_top` or directly in the testbench parameter block:

```verilog
// Example: 7 data bits, odd parity, 2 stop bits, 32-deep FIFO
uart_top #(
    .DATA_BITS(7),
    .PARITY_TYPE(2),
    .STOP_BITS(2),
    .ADDR_WIDTH(5)
) dut (...);
```

---

## Testbench and Verification

`tb_uart_top.v` is a self-checking testbench. No manual waveform inspection is needed — every comparison is automated and any mismatch increments `error_count` with full diagnostic output.

### Test 1 — Burst Write and Golden Reference Drain

Five bytes (`H`, `E`, `L`, `L`, `O` — `8'h48` through `8'h4F`) are written to the TX FIFO in a CPU burst without waiting for transmission to complete. The testbench then waits for `u_rx_fifo.data_count == 5` using a hardware-driven synchronization wait rather than a blind delay. Once the RX FIFO holds all five bytes, the testbench drains it and compares each output against a pre-loaded golden reference array.

The `wait(u_dut.u_rx_fifo.data_count == 5)` approach is hardware-driven — the testbench pauses for exactly as long as the silicon takes, regardless of baud rate or clock frequency. A blind `#delay` would break if either parameter changed. The wait is wrapped in a `fork...join_any` with a cycle-count watchdog so a hung simulation terminates with a diagnostic rather than running forever.

### Test 2 — RX FIFO Overrun Detection

`FIFO_DEPTH` bytes of `$random & 8'hFF` masked data are written to fill the RX FIFO to capacity. The `& 8'hFF` mask is explicit width control — `$random` returns a 32-bit signed integer and implicit truncation into an 8-bit array can produce sign-bit artifacts. The mask makes the sizing intentional.

Once the RX FIFO is confirmed full, a 17th byte (`8'hFF`) is transmitted. The testbench waits for `overrun_err` to pulse using a `fork...join_any` watchdog. On success, the RX FIFO is drained and each byte is compared against the golden reference array to confirm the original 16 bytes were not corrupted by the overrun event.

### Watchdog Pattern

Every `wait()` in the testbench is wrapped in a `fork...join_any` with a parallel timeout thread:

```verilog
fork
    begin : wait_block
        wait(condition);
    end
    begin : timeout_block
        repeat(N_CYCLES) @(posedge clk);
        $display("[FATAL] Timeout waiting for condition");
        $finish;
    end
join_any
disable fork;
```

A plain `wait()` with no timeout will freeze the simulator indefinitely if the RTL has a bug that prevents the condition from being met. The watchdog guarantees the simulation terminates cleanly regardless of RTL state.

---

## Simulation Results

```
=== STARTING PHASE 2 BURST TEST ===
-> CPU Burst Writing to TX FIFO...
Popped from RX FIFO: H (Hex: 48)
Popped from RX FIFO: E (Hex: 45)
Popped from RX FIFO: L (Hex: 4c)
Popped from RX FIFO: L (Hex: 4c)
Popped from RX FIFO: O (Hex: 4f)
--- TEST 2: RX OVERRUN ---
Firing 17th byte...
   [SUCCESS] Hardware pulsed overrun alert wire!
===ALL VERIFICATION TESTS PASSED!===
```

| Metric | Value |
|---|---|
| Test sequences | 2 |
| Burst transfer bytes verified | 5 |
| Overrun detection | Confirmed |
| Data corruption on overrun | None |
| Error count | 0 |
| Simulator | Vivado XSim 2025.2 |

---

## Toolchain

| Tool | Version | Purpose |
|---|---|---|
| Vivado | 2025.2 | Primary simulator (XSim behavioral simulation) |
| Icarus Verilog | 11+ | Optional open-source simulation |
| GTKWave | 3.3+ | Optional waveform viewer with iverilog |
| Git | — | Version control |

---

## Roadmap

- [x] **Phase 1** — Parameterized UART TX/RX with self-checking loopback testbench
- [x] **Phase 2** — Parameterized synchronous TX and RX FIFOs, overrun detection, burst-transfer testbench *(this release)*
- [ ] **Phase 3** — Fractional baud rate generator using accumulator-based approach; hardware RTS/CTS flow control
- [ ] **Phase 4** — AMBA APB slave wrapper with full memory-mapped register map (DR, SR, CR, IBRD, FBRD, IER, ISR); APB master BFM for testbench
- [ ] **Phase 5** — SystemVerilog constrained-random verification, functional coverage, code coverage, Python reference model, automated regression

---

## License

This project is open-source under the MIT License.

---

*Phase 2 of 5 — UART IP Core series. Built as a structured hardware design and verification learning project.*
