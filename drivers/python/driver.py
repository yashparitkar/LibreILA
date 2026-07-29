#####################################################################
# File: driver.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-07-24 Fri 19:48
# Last Modified: 2026-07-29 Wed 21:31
#
# Description: ILA Driver file
#   This file provides the core functions and structure for the ILA driver
#   This file does not provide any information for parsing the sample information
#####################################################################

import serial

# In python driver, wew are not checking for the setup parameters like in baremetal drivers

_libre_ila_status = {
    "LIBRE_ILA_STATUS_ERROR"    : -1,
    "LIBRE_ILA_STATUS_IDLE"     : 0,
    "LIBRE_ILA_STATUS_ARMED"    : 1,
    "LIBRE_ILA_STATUS_TRIGGERED": 2,
    "LIBRE_ILA_STATUS_DONE"     : 3
}

_libre_ila_trig_mode = {
    "LIBRE_ILA_TRIG_MODE_AND": 0,
    "LIBRE_ILA_TRIG_MODE_OR" : 1
}

_libre_ila_magic_key = 0xb01dface

# UART packet format, see the LibreILA UART Wrapper section of the README:
#
#   PC to ILA: | 0x55 | R/W (1) #words (7) | base address (32) | write words |
#   ILA to PC: | 0xAA | valid (1) #words (7) | base address (32) | read words |
#
# Every field wider than a byte goes MSB first. The wrapper answers both reads
# and writes with the response header, only a read is followed by data words.
_uart_sync_req        = 0x55
_uart_sync_resp       = 0xaa
_uart_req_write       = 0x80 # bit7 of the request byte, cleared for a read
_uart_resp_valid      = 0x80 # bit7 of the response byte
_uart_word_count_mask = 0x7f
_uart_max_words       = 0x7f # #words is a 7 bit field
_uart_header_len      = 6

def _check_request(base_address, count):
    """
    _check_request: Validate the address and the word count of a register access.

    base_address: The byte address of the first register of the access.
    count: The number of words in the access.

    returns: None
    """

    if base_address < 0 or base_address > 0xffffffff:
        raise ValueError(f"base address {base_address} does not fit in 32 bits")

    if base_address % 4:
        raise ValueError(f"base address 0x{base_address:08x} is not 4 byte aligned")

    if count < 0:
        raise ValueError(f"word count {count} is negative")

class LibreILA_Driver:
    def __init__(self, serial_port, baudrate=115200):
        self.serial_port = serial_port
        self.serial_connection = serial.Serial(serial_port, baudrate, timeout=1)

        self.status = 0

        self.probe_width = 0

        self.samp_buff_depth = 0
        self.samp_freq_hz = 0
        self.trigger_position = 0

        self.stride_width = 0
        self.axil_n_registers = 0

        self.output_reg_offset = 0

    def _recv(self, count):
        """
        _recv: Read exactly count bytes from the serial port.

        count: The number of bytes to read.

        returns: The bytes read.
        """

        data = bytearray()

        # A short read means the port timed out, so keep asking as long as the
        # wrapper is still feeding us something.
        while len(data) < count:
            chunk = self.serial_connection.read(count - len(data))

            if not chunk:
                raise TimeoutError(f"{self.serial_port}: timed out after {len(data)} of {count} bytes")

            data += chunk

        return bytes(data)

    def _transact(self, base_address, count, data=None):
        """
        _transact: Run one UART packet exchange with the wrapper.

        base_address: The byte address of the first register, 4 byte aligned.
        count: The number of words to transfer, at most _uart_max_words.
        data: The words to write, or None for a read.

        returns: vector of the words read, empty for a write.
        """

        is_write = data is not None

        packet = bytearray()
        packet.append(_uart_sync_req)
        packet.append((_uart_req_write if is_write else 0) | count)
        packet += base_address.to_bytes(4, "big")

        if is_write:
            for word in data:
                packet += (word & 0xffffffff).to_bytes(4, "big")

        # Whatever is still buffered predates this request, and the wrapper
        # drops every byte it cannot parse, so both ends start from a clean slate.
        self.serial_connection.reset_input_buffer()
        self.serial_connection.write(packet)
        self.serial_connection.flush()

        # The wrapper echoes the request back before it serves it, on writes too
        header = self._recv(_uart_header_len)

        if header[0] != _uart_sync_resp:
            raise OSError(f"bad sync byte 0x{header[0]:02x} in the response header")

        # The wrapper refuses a request whose address is misaligned or that
        # arrived after the RX FIFO dropped a byte. Nothing reached the AXI
        # bus, so the registers are untouched either way.
        if not header[1] & _uart_resp_valid:
            raise OSError(f"the wrapper refused the request at 0x{base_address:08x}, the address is "
                          f"misaligned or bytes were dropped on the way in")

        echo_count   = header[1] & _uart_word_count_mask
        echo_address = int.from_bytes(header[2:_uart_header_len], "big")

        if echo_count != count or echo_address != base_address:
            raise OSError(f"the wrapper echoed {echo_count} words at 0x{echo_address:08x}, "
                          f"expected {count} words at 0x{base_address:08x}")

        if is_write:
            return []

        payload = self._recv(4 * count)

        return [int.from_bytes(payload[i:i + 4], "big") for i in range(0, len(payload), 4)]

    def read_regs(self, base_address, count):
        """
        read_regs: Read the AXILite registers at the specified address.

        base_address: The address of the register to read.
        count: The number of words to read from the register array

        returns: vector of register values read from the specified address.
        """

        _check_request(base_address, count)

        values = []

        # #words is a 7 bit field, so a longer read is split over packets. The
        # wrapper is back in IDLE after each one, so its watchdog never sees the
        # gap between them.
        while len(values) < count:
            chunk   = min(count - len(values), _uart_max_words)
            values += self._transact(base_address + 4 * len(values), chunk)

        return values

    def write_regs(self, base_address, data):
        """
        write_regs: Write the AXILite registers at the specified address.

        base_address: The address of the register to write.
        data: data vector to write to the register array

        returns: None
        """

        data = list(data)

        _check_request(base_address, len(data))

        written = 0

        # Split over packets the same way as a read
        while written < len(data):
            chunk = min(len(data) - written, _uart_max_words)

            self._transact(base_address + 4 * written, chunk, data[written:written + chunk])

            written += chunk


    def get_status(self):
        """
        get_status: Get the status of the ILA driver.

        parameters: None

        returns: The status of the ILA driver.
        """
        None

    def set_trigger_position(self, position):
        """
        set_trigger_position: Set the trigger position of the ILA driver.

        position: The trigger position to set.

        returns: None
        """
        None

    def configure_trigger(self, trigger_cond, trigger_mask, trigger_mode):
        """
        configure_trigger: Configure the trigger mode and mask of the ILA driver.
        
        trigger_cond: The trigger condition to set.
        trigger_mask: The trigger mask to set.
        trigger_mode: The trigger mode to set.

        returns: None
        """
        None

    def arm(self):
        """
        arm: Arm the ILA driver to start capturing data when triggered.

        parameters: None

        returns: None
        """
        None

    def force_trigger(self):
        """
        force_trigger: Force the ILA driver to trigger and capture data.
        
        parameters: None
        
        returns: None
        """
        None

    def wait_done(self, timeout):
        """
        wait_done: Wait for the ILA driver to complete data capture.
        
        timeout: The maximum time to wait for the ILA driver to complete data capture.
        
        returns: None
        """
        None

    def read_idx(self, idx):
        """
        read_idx: Read the index of the first sample and the index of the sample where the trigger occurred.
        
        idx: The index of the sample to read.
        
        returns: [first_sample_idx, trigger_sample_idx]"""
        None

    def read_data(self):
        """
        read_data: Read the captured data from the ILA driver.
        
        parameters: None
        
        returns: The captured data from the ILA driver, arranged in a vector where each row corresponds to a sample arranged in time
        """
        None