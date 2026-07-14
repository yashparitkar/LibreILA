# AXI4 Slave ILA
This directory contains work related to AXI4 Stream In-System Logic Analyzer. 

The motivation to make this is follows:
* There is no ILA like in Xilinx toolchain in the Microchip toolchain, the SmartDebug can not replace the ILA
* ILA serves as a really good tool to debug the signals

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
|   3   |  W | Arm                 | Any write to this register arms the ILA |
|4      | RW | Trigger data (LSB)  | Input for TDATA trigger    |
|4+ a-1 | RW | Trigger data (LSB)  | Input for TDATA trigger    |
|4+ a   | RW | Trigger data mask (LSB)  | Input for TDATA trigger    |
|4+2a-1 | RW | Trigger data mask (MSB)  | Input for TDATA trigger    |

Here, a is the number of G_DATA_WIDTH/32

Further input register are auto added depending on the data width.

Total input registers: 4 + G_DATA_WIDTH/32 * 2

**Output (RO, index relative to the end of the input block):**

| Index | RW | Register Name       | Description                 |
|-------|----|---------------------|-----------------------------|
|   0   | RO | Status              | ILA status register         |
|   1   | RO | Magic key           | 0xb01dface                  |
|   2   | RO | samp_buff_trig_idx  | Index of the trigger sample |
|   3   | RO | samp_buff_frst_idx  | Index of the first sample   |
|  4+(a+1)i | RO | samp_buff(i) LSB    | ith sample in buffer LSB    |
| 4+(a+1)i+a| RO | samp_buff(i) MSB    | ith sample in buffer MSB    |

Total output registers: 4 + ( G_DATA_WIDTH/32 + 1) * G_DEPTH

Total number of registers: 8 + G_DATA_WIDTH/32 * 2 + (G_DATA_WIDTH/32 + 1) * G_DEPTH

## Trigger vector
Trigger vector decided when to trigger ILA. It is a 32 bit with register with mask and condition modifiable with AXI4Lite interface. Each bit of the vector corresponds to one of the condition being activated for trigger. The bit4 decides if the conditions are ORed or ANDed. If the TDATA is used as trigger, the value of TDATA can be entered in the trigger data input registers. When TDATA is used as a trigger, the MASK is supllied by the second set of registers of the TDATA width enabling mask of same size. 
> Mask serves enable for the condition check, i.e., TREADY will be checked only if the corresponding mask is '1'.

| Index | Signal             |
|-------|--------------------|
| 0     | TREADY             |
| 1     | TVALID             |
| 2     | TLAST              |
| 3     | TDATA              |
| 4     | < 0/1:AND/OR >     |

> Note that, mask corresponding to the bit4, < 0/1:AND/OR > is not checked.

## Output format
The output register can be seen in the above section. Internally, all the samples are stored in a LSRAM block. The AXI4Lite slave serves as read port for the RAM block. The offsetted read values are fed to the RAM port. This allows the design to make full use of the independent clock of the LSRAM of the PolarFire LSRAM block (G238606).

STATE HOW THE SIGNALS ARE APPENDED AND WORD ALIGNED WHILE STORING

## Serving suggestions
This design contains minimal AXI4S ports, user can add rest of the ports from the standard.
This can be further optimised for the data storage compression although I don't prefer that as it will make the readout complex.

If needed, user can also modify to use masked data values for triggering.

A simple softcore can be coupled with the core to give data output via SPI or some other protocol and read it out with PC. Even a software interface can be added to it.
