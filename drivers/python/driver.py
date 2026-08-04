#####################################################################
# File: driver.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-07-24 Fri 19:48
# Last Modified: 2026-08-01 Sat 14:18
#
# Description: ILA Driver file
#   This file provides the core functions and structure for the ILA driver
#   This file does not provide any information for parsing the sample information
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import time
import serial

# Nothing here is fixed at synthesis time. The baremetal driver has a reason to
# bake the probe width and buffer depth in, it sizes static buffers with them,
# but a host tool gains nothing from it and pays for it by having to be told
# what it is talking to. So the driver reads the lot back instead: the output
# block sits at the base address whatever the core was built with, and the part
# of the map that does move with the probe width follows from what it says.

_libre_ila_status = {
    "LIBRE_ILA_STATUS_ERROR"    : -1,
    "LIBRE_ILA_STATUS_IDLE"     : 0,
    "LIBRE_ILA_STATUS_ARMED"    : 1,
    "LIBRE_ILA_STATUS_TRIGGERED": 2,
    "LIBRE_ILA_STATUS_DONE"     : 3
}

_libre_ila_status_mask = {
    "LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_MASK" : 0x1,
    "LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_MASK" : 0x2,
    "LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_MASK"  : 0x4
}

# TRIG_CFG bit0 reduces the enabled bits of the trigger vector, bits 1 and 2
# decide what counts as a trigger on the reduced condition. They OR together,
# so LIBRE_ILA_TRIG_MODE_AND | LIBRE_ILA_TRIG_EDGE is "every enabled bit
# matches, and trigger when that becomes true" rather than "while it is true".
_libre_ila_trig_mode = {
    "LIBRE_ILA_TRIG_MODE_AND": 0,
    "LIBRE_ILA_TRIG_MODE_OR" : 1,
    "LIBRE_ILA_TRIG_EDGE"    : 2,
    "LIBRE_ILA_TRIG_FALLING" : 4
}

# Every bit TRIG_CFG defines. The core ignores anything above them, so a stray
# bit would leave the trigger in whatever mode the rest of the word asks for
# instead of failing, which is worth catching on the host.
_libre_ila_trig_mode_mask = 0x7

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

    # read_regs walks the address up by 4 per word, an access that runs off the
    # top would only fail once the packet builder hit the overflow mid loop
    if base_address + 4 * count > 0x100000000:
        raise ValueError(f"{count} words at 0x{base_address:08x} run past the end of the "
                         f"32 bit address space")

def _get_stride(n_lanes):
    """
    _get_stride: Registers one sample occupies in the AXI4Lite map.

    n_lanes: The number of 32 bit lanes the probe word needs.

    returns: The register stride, mirrors get_stride() in hdl/libre_ila.vhdl.
    """

    stride = 1

    # Next power of two at or above the lane count
    while stride < n_lanes:
        stride *= 2

    # The control registers always need four of them, whatever the probe width
    return max(stride, 4)

class LibreILA_Driver:
    def __init__(self, serial_port, baudrate=115200):
        self.serial_port = serial_port
        self.serial_connection = serial.Serial(serial_port, baudrate, timeout=1)

        self.LIBRE_ILA_REGS_STATUS_REG_OFFSET             = 0
        self.LIBRE_ILA_REGS_MGCKEY_REG_OFFSET             = 4
        self.LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET      = 8
        self.LIBRE_ILA_REGS_WIDTH_REG_OFFSET              = 12
        self.LIBRE_ILA_REGS_DEPTH_REG_OFFSET              = 16
        self.LIBRE_ILA_REGS_UID_REG_OFFSET                = 20
        self.LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET = 24
        self.LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET = 28

        # MGCKEY, SAMP_CLK_FREQ, WIDTH, DEPTH and UID are five registers in a
        # row, so one packet covers the lot.
        MGCKEY, self.SAMP_FREQ_HZ, self.PROBE_WIDTH, self.SAMP_BUFF_DEPTH, self.UID = \
                self.read_regs(self.LIBRE_ILA_REGS_MGCKEY_REG_OFFSET, 5)

        # Check the magic key to ensure that the wrapper is present and
        if MGCKEY != _libre_ila_magic_key:
            raise RuntimeError(f"{self.serial_port}: magic key mismatch, expected "
                               f"0x{_libre_ila_magic_key:08x}, got 0x{MGCKEY:08x}")

        # Simple error checks
        if self.PROBE_WIDTH < 1:
            raise RuntimeError(f"{self.serial_port}: the core reports a probe width of "
                               f"{self.PROBE_WIDTH} bits")

        if self.SAMP_BUFF_DEPTH < 2:
            raise RuntimeError(f"{self.serial_port}: the core reports a sample buffer "
                               f"{self.SAMP_BUFF_DEPTH} samples deep")

        # self.UID deliberately gets no check of its own: every value is legal
        # and zero means the core was built without one, so there is no wrong
        # uid to reject. It tells one core from another once the magic key has
        # established there is a core at all, which is why the two are separate
        # registers rather than one.

        # The lanes carry the probe word, the stride is what one sample takes
        # in the register map, padding included. They are not the same number:
        # the stock 67 bit probe needs 3 lanes but sits on a stride of 4.
        self.n_lanes      = (self.PROBE_WIDTH + 31) // 32
        self.stride_width = _get_stride(self.n_lanes)

        self.axil_n_op_registers = 8
        self.axil_n_ip_registers = 4 + 2 * self.stride_width

        # Everything from here on moves with the probe width, which is exactly
        # why it could not be worked out before the block above was read.
        self.LIBRE_ILA_INPUT_REG_OFFSET = self.axil_n_op_registers * 4

        self.LIBRE_ILA_REGS_TRIG_POS_REG_OFFSET = self.LIBRE_ILA_INPUT_REG_OFFSET
        self.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET   = self.LIBRE_ILA_INPUT_REG_OFFSET + 4
        self.LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET = self.LIBRE_ILA_INPUT_REG_OFFSET + 8
        self.LIBRE_ILA_REGS_DISARM_REG_OFFSET   = self.LIBRE_ILA_INPUT_REG_OFFSET + 12
        # The trigger vector starts above the four fixed control registers
        self.LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET = self.LIBRE_ILA_INPUT_REG_OFFSET + 16
        self.LIBRE_ILA_REGS_TRIG_MASK_REG_OFFSET = self.LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET \
                                                 + self.stride_width * 4

        self.LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET = \
                (self.axil_n_op_registers + self.axil_n_ip_registers) * 4

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

        # The STATE field of the same register carries the raw state machine
        # value, but it is not synchronised into the AXI clock domain. Decode
        # the CDCed ARMED/TRIGD/DONE bits instead, latest state first.
        status = self.read_regs(self.LIBRE_ILA_REGS_STATUS_REG_OFFSET, 1)[0]

        if status & _libre_ila_status_mask["LIBRE_ILA_REGS_STATUS_REG_DONE_FIELD_MASK"]:
            return _libre_ila_status["LIBRE_ILA_STATUS_DONE"]
        elif status & _libre_ila_status_mask["LIBRE_ILA_REGS_STATUS_REG_TRIGD_FIELD_MASK"]:
            return _libre_ila_status["LIBRE_ILA_STATUS_TRIGGERED"]
        elif status & _libre_ila_status_mask["LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_MASK"]:
            return _libre_ila_status["LIBRE_ILA_STATUS_ARMED"]
        else:
            return _libre_ila_status["LIBRE_ILA_STATUS_IDLE"]

    def set_trigger_position(self, position):
        """
        set_trigger_position: Set the trigger position of the ILA driver.

        position: The trigger position to set, in samples. 0 keeps the whole
        buffer for post trigger samples, depth-1 keeps it all for pre trigger
        ones.

        returns: None
        """

        if position < 0 or position >= self.SAMP_BUFF_DEPTH:
            raise ValueError(f"trigger position {position} is outside the "
                             f"{self.SAMP_BUFF_DEPTH} sample window")

        self.write_regs(self.LIBRE_ILA_REGS_TRIG_POS_REG_OFFSET, [position])

    def configure_trigger(self, trigger_cond, trigger_mask, trigger_mode):
        """
        configure_trigger: Configure the trigger mode and mask of the ILA driver.

        trigger_cond (vector of uint32) : The trigger condition to set, stride_width words.
        trigger_mask (vector of uint32) : The trigger mask to set, stride_width words.
        trigger_mode (uint32): The trigger mode to set, see _libre_ila_trig_mode.
            The reduction (AND or OR) OR-ed with the optional
            LIBRE_ILA_TRIG_EDGE and LIBRE_ILA_TRIG_FALLING flags. Without
            LIBRE_ILA_TRIG_EDGE the trigger is level sensitive, which fires on
            the first sample if the condition already holds when the ILA is
            armed. LIBRE_ILA_TRIG_FALLING is only meaningful alongside it.

        returns: None
        """

        trigger_cond = list(trigger_cond)
        trigger_mask = list(trigger_mask)

        # Both halves span the whole stride, the caller owns every bit of them
        # including the padding above the probe width.
        if len(trigger_cond) != self.stride_width:
            raise ValueError(f"trigger condition is {len(trigger_cond)} words, "
                             f"the stride is {self.stride_width}")

        if len(trigger_mask) != self.stride_width:
            raise ValueError(f"trigger mask is {len(trigger_mask)} words, "
                             f"the stride is {self.stride_width}")

        # TRIG_CFG defines bits 2 downto 0 and nothing else
        if trigger_mode < 0 or (trigger_mode & ~_libre_ila_trig_mode_mask) != 0:
            raise ValueError(f"trigger mode {trigger_mode} sets bits outside "
                             f"TRIG_CFG, only 0x{_libre_ila_trig_mode_mask:x} is defined")

        # Rising versus falling only means anything once the edge bit is set,
        # the core does not look at bit 2 in level mode. Asking for a falling
        # level trigger is a caller mistake worth naming rather than ignoring.
        if (trigger_mode & _libre_ila_trig_mode["LIBRE_ILA_TRIG_FALLING"]) and \
           not (trigger_mode & _libre_ila_trig_mode["LIBRE_ILA_TRIG_EDGE"]):
            raise ValueError("LIBRE_ILA_TRIG_FALLING needs LIBRE_ILA_TRIG_EDGE, "
                             "a level trigger has no direction")

        self.write_regs(self.LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET, trigger_cond)
        self.write_regs(self.LIBRE_ILA_REGS_TRIG_MASK_REG_OFFSET, trigger_mask)
        self.write_regs(self.LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET, [trigger_mode])

    def get_trigger_configuration(self):
        """
        get_trigger_configuration: Read the trigger setup back out of the core.

        parameters: None

        returns: A dict with trigger_cond and trigger_mask (stride_width words
        each, LSB word first), trigger_mode (the TRIG_CFG word) and
        trigger_position.
        """

        # The input register block reads back, so the core is the record of
        # what was written rather than the host having to remember it. That
        # is what lets one invocation configure the trigger and a later one
        # change a single field without disturbing the rest.
        trigger_position = self.read_regs(self.LIBRE_ILA_REGS_TRIG_POS_REG_OFFSET, 1)[0]
        trigger_mode     = self.read_regs(self.LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET, 1)[0]

        # TRIG_COND and TRIG_MASK are adjacent, stride_width words each, so
        # one read covers both halves of the trigger vector.
        trigger_vector = self.read_regs(self.LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET,
                                        2 * self.stride_width)

        return {
            "trigger_cond"    : trigger_vector[:self.stride_width],
            "trigger_mask"    : trigger_vector[self.stride_width:],
            "trigger_mode"    : trigger_mode,
            "trigger_position": trigger_position
        }

    def arm(self):
        """
        arm: Arm the ILA driver to start capturing data when triggered.

        parameters: None

        returns: None
        """

        status = self.read_regs(self.LIBRE_ILA_REGS_STATUS_REG_OFFSET, 1)[0]

        if status & _libre_ila_status_mask["LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_MASK"]:
            raise RuntimeError("the ILA is already armed, another write to ARM_FT "
                               "would force a trigger")

        # The hardware arms on the write itself, the value written does not matter
        self.write_regs(self.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET, [1])

    def force_trigger(self):
        """
        force_trigger: Force the ILA driver to trigger and capture data.
        
        parameters: None
        
        returns: None
        """

        status = self.read_regs(self.LIBRE_ILA_REGS_STATUS_REG_OFFSET, 1)[0]

        if not status & _libre_ila_status_mask["LIBRE_ILA_REGS_STATUS_REG_ARMED_FIELD_MASK"]:
            raise RuntimeError("the ILA is not armed, a write to ARM_FT would arm it instead")

        # Same register as the arm, an armed ILA reads the write as a forced
        # trigger. The value written does not matter here either.
        self.write_regs(self.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET, [2])

    def disarm(self):
        """
        disarm: Cancel a capture in progress and put the ILA back to idle.

        Works whether or not the trigger has already fired, so a capture left
        waiting on a condition that never comes, or one triggered by the wrong
        condition, can be taken back without resetting the core. The samples
        already taken stay in the buffer but stop counting as a capture.

        A completed capture is not discarded, the core ignores the write in
        that state, so this raises rather than pretending it did something.

        parameters: None

        returns: None
        """

        status = self.get_status()

        if status == _libre_ila_status["LIBRE_ILA_STATUS_IDLE"]:
            raise RuntimeError("the ILA is not armed, there is no capture to cancel")

        if status == _libre_ila_status["LIBRE_ILA_STATUS_DONE"]:
            raise RuntimeError("the capture has already completed, DISARM does not "
                               "discard it, arm again to start a new one")

        # Write triggered like ARM_FT, the value written does not matter
        self.write_regs(self.LIBRE_ILA_REGS_DISARM_REG_OFFSET, [1])

    def wait_done(self, timeout):
        """
        wait_done: Wait for the ILA driver to complete data capture.
        
        timeout: The maximum time to wait for the ILA driver to complete data capture.
        
        returns: None
        """
        start_time = time.time()

        while self.get_status() != _libre_ila_status["LIBRE_ILA_STATUS_DONE"]:
            if time.time() - start_time > timeout:
                raise TimeoutError(f"{self.serial_port}: timed out waiting for the ILA driver to complete data capture")

            time.sleep(0.001)

    def read_idx(self):
        """
        read_idx: Read the index of the first sample and the index of the sample where the trigger occurred.

        parameters: None

        returns: [first_sample_idx, trigger_sample_idx], both raw indices into
        the circular buffer rather than positions in a time ordered readback.
        """

        # Adjacent registers, TRIG_IDX first
        trig_idx, frst_idx = self.read_regs(self.LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET, 2)

        return [frst_idx, trig_idx]

    def read_data(self):
        """
        read_data: Read the captured data from the ILA driver.

        parameters: None

        returns: (samples, trigger_sample_idx). samples is the captured data
        from the ILA driver, arranged in a vector where each row corresponds to
        a sample arranged in time, oldest first, each row holding the n_lanes
        words of the probe word. trigger_sample_idx is the row the trigger
        fired on.
        """

        frst_idx, trig_idx = self.read_idx()

        # Both indices point into the circular buffer, the readback below
        # unrolls it from the oldest sample, so rebase the trigger onto it.
        trig_idx = (trig_idx + self.SAMP_BUFF_DEPTH - frst_idx) % self.SAMP_BUFF_DEPTH

        words = self.read_regs(self.LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET,
                               self.SAMP_BUFF_DEPTH * self.stride_width)

        samples = []

        # A sample takes stride_width registers in hardware but only the first
        # n_lanes of them carry probe bits, the rest is padding and gets
        # dropped here.
        for i in range(self.SAMP_BUFF_DEPTH):
            base = ((frst_idx + i) % self.SAMP_BUFF_DEPTH) * self.stride_width

            samples.append(words[base:base + self.n_lanes])

        return samples, trig_idx

    def close(self):
        """
        close: Close the serial connection to the ILA driver.

        parameters: None

        returns: None
        """

        self.serial_connection.close()
