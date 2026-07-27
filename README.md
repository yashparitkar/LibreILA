# LibreILA

This project contains work related to LibreILA (In-System Logic Analyzer). 

The motivation to make this is follows:
* There is no ILA like in Xilinx toolchain in the Microchip toolchain, the SmartDebug can not replace the ILA
* ILA serves as a really good tool to debug the signals

This specific ILA is specialised for the AXI4S but a similar logic can be modified and easily adapted for generic IOs.

## License 

This project is licensed under CERN Open Hardware Licence Version 2 - Permissive unless otherwise specified. See LICENSE for more details.

## Features
* Optional external trigger port to synchronise with other ILAs
* Uses fabric ram for data storage and can be read back with AXI4Lite interface
* Data acquisition happens continously in a circular buffer
* Pass through AXI4 Stream ports ensures no delay is introduced due to the IP
* Customizable trigger:
    * Trigger can be set with AXI4Lite interface
    * Any AXI4S signal can be set as a trigger condition
    * Once setting the triggers condition, the ILA can be armed
    * Number of samples before and after trigger can be adjusted
    * Can also use a external trigger
* CDC on the ARM and status bits
* A serial wrapper is also provided to easily use the ILA with the PC
* A python driver is provided to easily control the ILA from the PC when instantiated with the serial wrapper

# LibreILA core
This section contains information about the LibreILA core.

## Ports
Current implementation only uses TDATA, TVALID, TREADY and TLAST ports. 
* axis_in: AXI4S Slave port: Serves as slave port for the master.
* axis_out: AXI4S Master port: Serves as master port for the slave
* axil: AXI4Lite Slave port: Configuration and readout port
* i_ext_trig: external trigger port
* o_trig_out: internal trigger signal for chaining to other ILA instances

## Configuration Parameters
* G_EXTERNAL_TRIG : 1: Use external trigger
* G_DATA_WIDTH    : Width of the AXI4S, keep it multiple of 32
* G_DEPTH         : Number of samples to store, keep it power of two

## axi4lite Register Map

32-bit registers; byte address = `Index * 4`. Sizing auto-scales with data width and depth.

### Input (RW)

| Index  | RW | Register Name          | Description                 |
|--------|----|-------------------------|-----------------------------|
|   0    | RW | Trigger position        | Number of pre-trig samples  |
|   1    |  W | Arm_FT                  | Any write to this register arms the ILA or forces trigger if already armed |
|   2    | RW | Trigger configuration   | bit0: 0 = AND, 1 = OR. See trigger vector section |
|   3    | RW | Reserved                | Reserved                    |
| 4      | RW | Trigger vector cond (LSB) | See trigger vector section |
| 4+a-1  | RW | Trigger vector cond (MSB) |                            |
| 4+a    | RW | Trigger vector mask (LSB) |                            |
| 4+2a-1 | RW | Trigger vector mask (MSB) |                            |

Here, `a` is `C_AXIL_STRIDE`: the same stride constant used to lay out the output sample buffer (see below), i.e. the next power-of-two register count for (TDATA lanes + 1 control lane), with a minimum of 4. This makes the trigger vector cond/mask registers share the exact same per-sample bit layout as the output sample buffer.

Further input registers are auto added depending on the data width.

Total input registers: 4 + C_AXIL_STRIDE * 2

### Output (RO, index relative to the end of the input block)

| Index | RW | Register Name       | Description                           |
|-------|----|---------------------|---------------------------------------|
|   0   | RO | Status              | ILA status register                   |
|   1   | RO | Magic key           | 0xb01dface                            |
|   2   | RO | Samp Clk Freqcy     | Sampling clock frequency (Hz)         |
|   3   | RO | Width               | #signals(16bit) & axi4s width (16bit) |
|   4   | RO | Buffer Depth        | Depth of the sampling buffer          |
|   5   | RO | Reserved            | Reserved                              |
|   6   | RO | samp_buff_trig_idx  | Index of the trigger sample           |
|   7   | RO | samp_buff_frst_idx  | Index of the first sample             |

After this, sampling buffer is mapped with strides to ease the resource usage on the fabric. Each samp_buff is written as a bunch with number of registers used for each samp_buff as power of two to ease computation. For example, if the G_DATA_WIDTH is kept 64 and number of signals is 3 then total 4 32-bit registers are needed to properly show the data. Hence, stride will be of 4. Inside each stride, the data each stored in following format:
 
| Offset   | RW | Register Name                            | Description                |
|---------|----|------------------------------------------|----------------------------|
|  0       | RO | samp_buff(31 downto  0)                  | The LSBs of the AXI4S data |
|  1       | RO | samp_buff(63 downto 32)                  |                            |
| stride-2 | RO | samp_buff(G_DEPTH-1  downto G_DEPTH-32 ) | The MSBs of the AXI4S data |
| stride-1 | RO | samp_buff(G_DEPTH+31 downto G_DEPTH    ) | AXI4S signals              |

Total output registers: 8 + ( G_DATA_WIDTH/32 + 1) * G_DEPTH

Total number of registers: 12 + C_AXIL_STRIDE * 2 + (G_DATA_WIDTH/32 + 1) * G_DEPTH

#### Status 
This is the status register of the ILA. The ARMED, TRIGD and DONE signal bits are CDCed with 2FF to the AXI4Lite domain and hence suffer a slight delay. The internal status register does not have CDC and used for debugging.
| bit | Name   | Description                                  |
|-----|--------|----------------------------------------------|
|  0  | ARMED  | High if the ILA is armed                     |
|  1  | TRIGD  | High if the trigger happens                  |
|  2  | DONE   | Marks the completion of the ILA process      |
| 4-3 | STATUS | Internal status register of the ILA (No CDC) |

## Trigger vector
The trigger vector, condition and mask registers are merged into a single, unified per-bit vector that shares the exact same bit layout as one row of the output sample buffer (see the AXI4Lite register map and the output register section above): TDATA occupies the low bits, followed by the AXI4S control signals, followed by reserved/padding bits up to the `C_AXIL_STRIDE`-register boundary.

| Bit range                              | Signal                          |
|-----------------------------------------|---------------------------------|
| G_DATA_WIDTH-1 downto 0                 | TDATA                           |
| G_DATA_WIDTH                            | TLAST                           |
| G_DATA_WIDTH+1                          | TVALID                          |
| G_DATA_WIDTH+2                          | TREADY                          |
| G_DATA_WIDTH+3 to (C_AXIL_STRIDE*32)-1  | Reserved (leave mask bit at '0') |

For every bit, the corresponding cond bit is the expected value of that signal and the corresponding mask bit enables that bit for the trigger check (`mask='1'` means the bit participates; `mask='0'` means it's ignored). A bit is considered "matching" when the live signal equals its cond bit.

The trigger configuration register (index 2, bit0) selects how the enabled bits are combined:
* `0` (AND): the ILA triggers only once **every** enabled bit is matching.
* `1` (OR): the ILA triggers as soon as **any** enabled bit is matching.

Since TDATA now participates in the same per-bit vector as the control signals, individual TDATA bits can be combined with TREADY/TVALID/TLAST in either AND or OR mode -- there is no longer a separate, single-bit "whole word matches" path for TDATA.

## Trigger

### External Trigger
The external trigger is a bit-wide input port. Use of external port needs to be enabled at the time of instantiation. The signal is synchronised to the AXI4S clock domain and rising edge of the signal is used to trigger the ILA.

## Output format
The output register can be seen in the above section. Internally, all the samples are stored in a LSRAM block. The AXI4Lite slave serves as read port for the RAM block. The offsetted read values are fed to the RAM port. This allows the design to make full use of the independent clock of the LSRAM of the PolarFire LSRAM block (Microchip document G238606).

STATE HOW THE SIGNALS ARE APPENDED AND WORD ALIGNED WHILE STORING

## Clock domains
The core operates in the sampling clock domain which is AXI4S in the default case. The AXI4Lite is separate domain.

## Serving suggestions
This design contains minimal AXI4S ports, user can add rest of the ports from the standard.

This can be further optimised for the data storage compression although I don't prefer that as it will make the readout complex.

If needed, user can also modify to use masked data values for triggering.

# LibreILA UART Wrapper
This section contains information about the LibreILA UART Wrapper (libre_ila_uart.vhdl).

## UART packet format
The PC is the one managing the ILA. It is connected to the ILA with the UART interface. A custom packet format is defined to read/write the addresses. The packet format for the upstream and downstream is given below.

### PC to ILA WRAPPER
```text
| SYNC/VALID | R/W | #words | base address | Write Data Words | 
|     0x55   | 0/1 | 7 bit  |   32-bits    | 32-bits x #words | 
```

### ILA WRAPPER to PC
```text
| SYNC/VALID | valid | #words | base address | Read Data Words  | 
|     0xAA   | 0/1   | 7 bit  |   32-bits    | 32-bits x #words | 
```

## Clock domains
The core operates in the sampling clock domain which is AXI4S in the default case. The AXI4Lite domain clock is kept separate. This block operates on the AXI4Lite clock. The UART clock is derived from the AXI4Lite clock.

## Watchdog timer
The wrapper has a watchdog timer to reset the wrapper in case of any error. The timer is incremented in non-IDLE mode and is reset when a byte is succefully is received via UART or AXI interface. A reset is issued when the timer reaches a certain value.

# Future improvements

## A script to modify the probe port
A python script can be written to modify the probed port. This can be done by reading a configuration from csv file. Support for the inout port can also be added.
The script will need to modify the port declarations and signal concatment. This method will also make it easier to write a script which generate modified vhdl based on other parameter such as existance of the i_ext_trig port, writing default generics.