# AXI4 Slave ILA
This directory contains work related to AXI4 Stream In-System Logic Analyzer. 

The motivation to make this is follows:
* There is no ILA like in Xilinx toolchain in the Microchip toolchain, the SmartDebug can not replace the ILA
* ILA servers as a really good tool to debug the signals

This specific ILA is specialised for the AXI4S but a similar logic can be modified and easily adapted for generic IOs.

## Features
* Optional external trigger port to synchronise with other ILAs
* Uses fabric ram for data storage and can be read back with AXI4Lite interface
* Data acquisition happens continously in a circular buffer
* Pass through AXI4 Stream ports ensures no delay is introduced due to the IP
* Customizable trigger:
1. Trigger can be set with AXI4Lite interface
2. Any AXI4S signal can be set as a trigger condition
3. Once setting the triggers condition, the ILA can be armed
4. Number of samples before and after trigger can be adjusted
5. Can also use a external trigger

## Ports
Current implementation only uses TDATA, TVALID, TREADY and TLAST ports. 
* axis_in: AXI4S Slave port: Serves as slave port for the master.
* axis_out: AXI4S Master port: Serves as master port for the slave
* axil: AXI4Lite Slave port: Configuration and readout port
* i_ext_trig: external trigger port
* o_trig_out: internal trigger signal for chaining to other ILA instances

## Configuration Parameters
* Buffer size

## axi4lite Register Map

32-bit registers; byte address = `Index * 4`. Sizing auto-scales with data width and depth.

**Input (RW):**

| Index | RW | Register Name       | Description                |
|-------|----|---------------------|----------------------------|
|   0   | RW | Trigger vector cond | See trigger vector section |
|   1   | RW | Trigger vector mask |                            |
|   2   | RW | Trigger position    | Number of pre-trig samples |
|   3   | RW | Trigger data (LSB)  | Input for TDATA trigger    |

Further input register are auto added depending on the data width.

Total input registers: 3 + G_DATA_WIDTH

**Output (RO, index relative to the end of the input block):**

| Index | RW | Register Name       | Description                 |
|-------|----|---------------------|-----------------------------|
|   0   | RO | Status              | ILA status register         |
|   1   | RO | Magic key           | Unique value to verify conn |
|   2   | RO | samp_buff_trig_idx  | Index of the trigger sample |
|   3   | RO | samp_buff_frst_idx  | Index of the first sample   |
|  4+2i | RO | samp_buff(i) LSB    | ith sample in buffer LSB    |
| 4+2i+1| RO | samp_buff(i) MSB    | ith sample in buffer MSB    |

## Trigger vector
Trigger vector decided when to trigger ILA. It is a 32 bit with register with mask and condition modifiable with AXI4Lite interface. Each bit of the vector corresponds to one of the condition being activated for trigger. The bit4 decides if the conditions are ORed or ANDed. If the TDATA is used as trigger, the value of TDATA can be entered in the trigger data input registers.

| Index | Signal             |
|-------|--------------------|
| 0     | TREADY             |
| 1     | TVALID             |
| 2     | TLAST              |
| 3     | TDATA              |
| 4     | < 0/1:AND/OR >     |

## Output format

## Serving suggestions
This design contains minimal AXI4S ports, user can add rest of the ports from the standard.
This can be further optimised for the data storage compression although I don't prefer that as it will make the readout complex.

If needed, user can also modify to use masked data values for triggering.

A simple softcore can be coupled with the core to give data output via SPI or some other protocol and read it out with PC. Even a software interface can be added to it.
