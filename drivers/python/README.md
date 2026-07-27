# LibreILA Python driver
This directory contains the python driver for the LibreILA IP. The driver is used to control the LibreILA when instantiated as libre_ila_uart.vhdl

## Requirements
Following packages are required:
* pyserial: `sudo apt install python3-serial`

## Setting the signal mapping
The signal mapping is read from the portmap.csv file. It has three columns, namely, signal, width, type. The ports should be entered as seen by the master of the line where the probe is attached. For example, if the probe is used for AXI4S, then the portmap should contain port details of the AXI4S Slave. The signals are written LSB aligned, i.e., if the stride of the AXI registers is 2, then we have 63:0 signals. The signal with range 3:0 should be written first, then signal 4:4.

* signal: the name of the signal to be displayed in the .vcd
* width: width of the signal in bits
* type: in/out/inout (planning to write a generation script in the future)

For example, the portmap.csv file for the AXI4S will be as follows:
```portmap.csv
axis_tdata,64,in
axis_tlast,1,in
axis_tvalid,1,in
axis_tready,1,out
```
