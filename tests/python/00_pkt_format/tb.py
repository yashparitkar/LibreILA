#####################################################################
# File: tb.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-07-29 Wed 20:35
# Last Modified: 2026-07-31 Fri 11:19
#
# Description: Packet format test for the python driver
#   Checks drivers/python/driver.py against a model of the wrapper's
#   packet parser. This is a host side test, there is no GHDL and no
#   generated core involved, so it runs anywhere python does.
#####################################################################

import os
import sys
import types
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "drivers", "python"))

# driver.py imports pyserial at module scope and this test never opens a real
# port, so a stub stands in for it. Keeps the test free of the pyserial
# dependency and keeps a stray /dev node from ever being touched.
_pending_port = None

def _fake_serial(port, baudrate=115200, timeout=None):
    """
    _fake_serial: Stand in for serial.Serial.

    port: Ignored, no port is opened.
    baudrate: Ignored.
    timeout: Ignored.

    returns: The FakeWrapper the test staged in _pending_port.
    """
    return _pending_port

_serial_stub        = types.ModuleType("serial")
_serial_stub.Serial = _fake_serial
sys.modules["serial"] = _serial_stub

import driver

class FakeWrapper:
    """
    FakeWrapper: A byte level model of p_main in hdl/libre_ila_uart.vhdl.

    IUW_IDLE drops every byte that is not 0x55, IUW_REQ takes the R/W bit and
    the 7 bit word count, IUW_ADDR takes four address bytes MSB first, IUW_HDR
    emits 0xAA, the valid bit with the word count and the address, and then
    IUW_RD/IUW_WR move the data words MSB first with the address advancing by
    four per word. The response header is emitted for a write too.
    """

    def __init__(self, mem=None):
        self.mem     = dict(mem or {}) # byte address -> 32 bit word
        self.rx      = bytearray()     # sent by the PC, not parsed yet
        self.tx      = bytearray()     # waiting for the PC to read
        self.packets = []              # ("r"/"w", count, address) as parsed
        self.flushes = 0

    # pyserial surface ------------------------------------------------------
    def read(self, count):
        data = bytes(self.tx[:count])
        del self.tx[:count]

        return data

    def write(self, data):
        self.rx += data
        self._run()

        return len(data)

    def flush(self):
        None

    def reset_input_buffer(self):
        self.flushes += 1
        self.tx.clear()

    # the wrapper's state machine -------------------------------------------
    def _run(self):
        while self.rx:
            # IUW_IDLE: flush anything that is not a sync byte
            if self.rx[0] != 0x55:
                del self.rx[0]
                continue

            if len(self.rx) < 6:
                return

            request  = self.rx[1]
            count    = request & 0x7f
            address  = int.from_bytes(self.rx[2:6], "big")
            is_write = bool(request & 0x80)

            # IUW_WR fetches the data words a byte at a time, so nothing
            # happens until the whole packet has landed
            if is_write and len(self.rx) < 6 + 4 * count:
                return

            del self.rx[:6]
            self.packets.append(("w" if is_write else "r", count, address))

            # IUW_HDR, the valid bit is hardwired to '1' in the RTL
            self.tx.append(0xaa)
            self.tx.append(0x80 | count)
            self.tx += address.to_bytes(4, "big")

            for i in range(count):
                if is_write:
                    self.mem[address + 4 * i] = int.from_bytes(self.rx[:4], "big")
                    del self.rx[:4]
                else:
                    self.tx += self.mem.get(address + 4 * i, 0).to_bytes(4, "big")

# The stock AXI4S build, 64 bits of TDATA plus the three signalling bits
_PROBE_WIDTH = 67
_DEPTH       = 2048
_FREQ_HZ     = 100000000

def identity_regs(probe_width=_PROBE_WIDTH, depth=_DEPTH, freq=_FREQ_HZ):
    """
    identity_regs: The registers LibreILA_Driver reads while constructing.

    probe_width: The probe width the core is to report.
    depth: The sample buffer depth the core is to report.
    freq: The sampling clock frequency the core is to report.

    returns: byte address -> word, ready to seed a FakeWrapper.

    The offsets are worked out here from the register map in the top level
    README rather than taken from the driver, so a driver that derives them
    wrong fails to construct instead of agreeing with itself.
    """

    # The output block sits at the base address and is eight registers wide
    # whatever the probe width is, so none of these move.
    return {
        0x04 : 0xb01dface,  # MGCKEY
        0x08 : freq,        # SAMP_CLK_FREQ
        0x0c : probe_width, # WIDTH
        0x10 : depth        # DEPTH
    }

def raw_driver(wrapper):
    """
    raw_driver: Construct a driver against a wrapper exactly as it was staged.

    wrapper: The FakeWrapper to answer the driver's traffic.

    returns: The LibreILA_Driver instance.

    Unlike make_driver this seeds nothing, so the checks in __init__ see
    whatever the test put in the wrapper.
    """
    global _pending_port

    _pending_port = wrapper

    return driver.LibreILA_Driver("/dev/null")

def make_driver(wrapper, probe_width=_PROBE_WIDTH, depth=_DEPTH):
    """
    make_driver: Build a driver bound to a FakeWrapper instead of a real port.

    wrapper: The FakeWrapper to answer the driver's traffic.
    probe_width: The probe width the core is to report.
    depth: The sample buffer depth the core is to report.

    returns: The LibreILA_Driver instance.
    """

    # The driver builds its whole register map out of the identity registers
    # while constructing, so they win over anything the test staged
    wrapper.mem.update(identity_regs(probe_width, depth))

    ila = raw_driver(wrapper)

    # Hide the construction traffic, the tests below count their own packets
    wrapper.packets.clear()
    wrapper.flushes = 0

    return ila

class TestPacketFormat(unittest.TestCase):
    """
    TestPacketFormat: The bytes on the wire, checked against the reference
    procedures uart_ila_read and uart_ila_write in
    tests/hdl/06_sim_libre_ila_uart/tb.vhdl.
    """

    def test_read_request_bytes(self):
        # above the control registers, those are the driver's own
        wrapper = FakeWrapper({0x140: 0xb01dface, 0x144: 0xdeadbeef})
        ila     = make_driver(wrapper)
        sent    = []

        wrapper.write = lambda d, _w=wrapper.write: (sent.append(bytes(d)), _w(d))[1]

        self.assertEqual(ila.read_regs(0x140, 2), [0xb01dface, 0xdeadbeef])

        # 0x55, R with 2 words, then the address MSB first
        self.assertEqual(sent[0], bytes([0x55, 0x02, 0x00, 0x00, 0x01, 0x40]))

    def test_write_request_bytes(self):
        wrapper = FakeWrapper()
        ila     = make_driver(wrapper)
        sent    = []

        wrapper.write = lambda d, _w=wrapper.write: (sent.append(bytes(d)), _w(d))[1]

        self.assertIsNone(ila.write_regs(0x100, [0x11223344, 0x55667788]))

        # 0x55, W with 2 words, the address and both words MSB first
        self.assertEqual(sent[0], bytes([0x55, 0x82, 0x00, 0x00, 0x01, 0x00,
                                         0x11, 0x22, 0x33, 0x44,
                                         0x55, 0x66, 0x77, 0x88]))
        # mem also carries the identity registers the driver read on the way up
        self.assertEqual(wrapper.mem[0x100], 0x11223344)
        self.assertEqual(wrapper.mem[0x104], 0x55667788)

    def test_write_ack_is_drained(self):
        """The wrapper answers a write with a header too, leaving it in the
        buffer would desync the next transaction."""
        wrapper = FakeWrapper()
        ila     = make_driver(wrapper)

        ila.write_regs(0x0, [0x1234])
        self.assertEqual(len(wrapper.tx), 0)

        # and the next read still lines up
        self.assertEqual(ila.read_regs(0x0, 1), [0x1234])

    def test_roundtrip(self):
        wrapper = FakeWrapper()
        ila     = make_driver(wrapper)
        words   = [(i * 0x01010101) & 0xffffffff for i in range(64)]

        ila.write_regs(0x200, words)
        self.assertEqual(ila.read_regs(0x200, 64), words)

class TestChunking(unittest.TestCase):
    """
    TestChunking: #words is a 7 bit field, so anything longer than 127 words
    has to be split. A stock 2048 deep buffer at stride 4 is 8192 words, so
    every full readout takes this path.
    """

    def test_write_splits_at_127(self):
        wrapper = FakeWrapper()
        ila     = make_driver(wrapper)
        words   = [0x1000 + i for i in range(300)]

        ila.write_regs(0x80, words)

        self.assertEqual([p[:2] for p in wrapper.packets],
                         [("w", 127), ("w", 127), ("w", 46)])
        # each packet picks up where the last one left off, 4 bytes per word
        self.assertEqual([p[2] for p in wrapper.packets],
                         [0x80, 0x80 + 127 * 4, 0x80 + 254 * 4])
        self.assertEqual(ila.read_regs(0x80, 300), words)

    def test_read_splits_at_127(self):
        wrapper = FakeWrapper({0x80 + 4 * i: 0x2000 + i for i in range(300)})
        ila     = make_driver(wrapper)

        self.assertEqual(ila.read_regs(0x80, 300), [0x2000 + i for i in range(300)])
        self.assertEqual([p[:2] for p in wrapper.packets],
                         [("r", 127), ("r", 127), ("r", 46)])

    def test_full_sample_buffer(self):
        """The readout read_data will do on the stock build."""
        depth   = 2048
        stride  = 4
        base    = 0x100
        content = {base + 4 * i: (0xa5a50000 + i) & 0xffffffff for i in range(depth * stride)}
        wrapper = FakeWrapper(content)
        ila     = make_driver(wrapper)

        values = ila.read_regs(base, depth * stride)

        self.assertEqual(len(values), depth * stride)
        self.assertEqual(values, [content[base + 4 * i] for i in range(depth * stride)])
        # 8192 words in packets of at most 127
        self.assertEqual(len(wrapper.packets), 65)
        self.assertTrue(all(p[1] <= 127 for p in wrapper.packets))

    def test_zero_count_sends_nothing(self):
        wrapper = FakeWrapper()
        ila     = make_driver(wrapper)

        self.assertEqual(ila.read_regs(0x0, 0), [])
        ila.write_regs(0x0, [])

        self.assertEqual(wrapper.packets, [])

class TestErrorHandling(unittest.TestCase):
    """
    TestErrorHandling: every failure has to surface as an exception. The
    caller treats any of them as a lost transaction and restarts.
    """

    def test_stale_bytes_are_flushed(self):
        # 0x100 is scratch, anywhere past the identity block at 0x00..0x1c
        # would do, that block gets seeded over whatever is staged here.
        wrapper = FakeWrapper({0x100: 0xcafebabe})
        ila     = make_driver(wrapper)

        wrapper.tx += b"\x00\x01\x02" # leftovers from an aborted transfer

        self.assertEqual(ila.read_regs(0x100, 1), [0xcafebabe])

    def test_negative_word_is_masked(self):
        wrapper = FakeWrapper()
        ila     = make_driver(wrapper)

        ila.write_regs(0x0, [-1])

        self.assertEqual(wrapper.mem[0x0], 0xffffffff)

    def test_bad_address_or_count(self):
        ila = make_driver(FakeWrapper())

        for address, count in ((0x2, 1), (-4, 1), (0x1_0000_0000, 1), (0x0, -1)):
            with self.assertRaises(ValueError):
                ila.read_regs(address, count)

        with self.assertRaises(ValueError):
            ila.write_regs(0x2, [0])

    def test_bad_sync_byte(self):
        wrapper       = FakeWrapper({0x0: 1})
        ila           = make_driver(wrapper)
        wrapper.write = lambda d: wrapper.tx.extend(b"\x5a" * 6)

        with self.assertRaises(OSError):
            ila.read_regs(0x0, 1)

    def test_valid_bit_clear(self):
        wrapper       = FakeWrapper({0x0: 1})
        ila           = make_driver(wrapper)
        wrapper.write = lambda d: wrapper.tx.extend(bytes([0xaa, 0x01, 0, 0, 0, 0]))

        with self.assertRaises(OSError):
            ila.read_regs(0x0, 1)

    def test_echo_mismatch(self):
        wrapper       = FakeWrapper({0x0: 1})
        ila           = make_driver(wrapper)
        wrapper.write = lambda d: wrapper.tx.extend(bytes([0xaa, 0x81, 0, 0, 0, 0x40]))

        with self.assertRaises(OSError):
            ila.read_regs(0x0, 1)

    def test_timeout_on_missing_data(self):
        """Header lands, the data words never do, as after a watchdog reset."""
        wrapper       = FakeWrapper({0x0: 1})
        ila           = make_driver(wrapper)
        wrapper.write = lambda d: wrapper.tx.extend(bytes([0xaa, 0x81, 0, 0, 0, 0]))

        with self.assertRaises(TimeoutError):
            ila.read_regs(0x0, 1)

    def test_timeout_is_an_oserror(self):
        """main.py restarts on any lost transaction, so one except clause has
        to cover both the timeout and the desync cases."""
        self.assertTrue(issubclass(TimeoutError, OSError))

class TestRegisterMap(unittest.TestCase):
    """
    TestRegisterMap: The offsets the driver derives from the probe width,
    against the map in the register summary of docs/datasheet.pdf and in
    drivers/baremetal/core_libre_ila_regs.h. Everything scales with the stride,
    which is the lane count rounded up to a power of two with a minimum of
    four, so the lane count on its own is not it.
    """

    def test_stock_axi4s_build(self):
        ila = make_driver(FakeWrapper(), 67)

        # 67 bits need 3 lanes, and 3 rounds up to a stride of 4
        self.assertEqual(ila.n_lanes, 3)
        self.assertEqual(ila.stride_width, 4)

        # The output block is first and fixed, the input block starts above it
        self.assertEqual(ila.LIBRE_ILA_REGS_STATUS_REG_OFFSET, 0x00)
        self.assertEqual(ila.LIBRE_ILA_REGS_TRIG_POS_REG_OFFSET, 0x20)
        self.assertEqual(ila.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET, 0x24)
        self.assertEqual(ila.LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET, 0x28)
        # 0x2C is the reserved input register, not the trigger vector
        self.assertEqual(ila.LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET, 0x30)
        self.assertEqual(ila.LIBRE_ILA_REGS_TRIG_MASK_REG_OFFSET, 0x40)
        self.assertEqual(ila.LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET, 0x50)

    def test_stride_rounds_up_to_a_power_of_two(self):
        for probe_width, n_lanes, stride in ((1, 1, 4), (67, 3, 4), (128, 4, 4),
                                             (129, 5, 8), (256, 8, 8), (257, 9, 16)):
            with self.subTest(probe_width=probe_width):
                ila = make_driver(FakeWrapper(), probe_width)

                self.assertEqual((ila.n_lanes, ila.stride_width), (n_lanes, stride))

                # The output block never moves, whatever the stride turns out
                # to be. Only what sits above it does.
                self.assertEqual(ila.LIBRE_ILA_REGS_STATUS_REG_OFFSET, 0x00)
                self.assertEqual(ila.LIBRE_ILA_REGS_TRIG_POS_REG_OFFSET, 0x20)
                self.assertEqual(ila.LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET, 0x30)
                self.assertEqual(ila.LIBRE_ILA_REGS_TRIG_MASK_REG_OFFSET, 0x30 + stride * 4)
                self.assertEqual(ila.LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET,
                                 (8 + 4 + 2 * stride) * 4)

    def test_output_registers_are_in_order(self):
        ila  = make_driver(FakeWrapper())
        base = ila.LIBRE_ILA_REGS_STATUS_REG_OFFSET

        self.assertEqual(base, 0x00)
        self.assertEqual(ila.LIBRE_ILA_REGS_MGCKEY_REG_OFFSET, base + 4)
        self.assertEqual(ila.LIBRE_ILA_REGS_SAMP_CLK_FREQ_REG_OFFSET, base + 8)
        self.assertEqual(ila.LIBRE_ILA_REGS_WIDTH_REG_OFFSET, base + 12)
        self.assertEqual(ila.LIBRE_ILA_REGS_DEPTH_REG_OFFSET, base + 16)
        # base + 20 is the reserved output register
        self.assertEqual(ila.LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET, base + 24)
        self.assertEqual(ila.LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET, base + 28)

    def test_synthesis_parameters_are_read_back(self):
        ila = make_driver(FakeWrapper(), 67, 4096)

        self.assertEqual(ila.samp_buff_depth, 4096)
        self.assertEqual(ila.samp_freq_hz, _FREQ_HZ)

class TestIdentityChecks(unittest.TestCase):
    """
    TestIdentityChecks: The register map is built out of what the identity
    block says, and the core truncates an address it cannot decode rather than
    rejecting it, so a driver pointed at something that is not a LibreILA gets
    answers instead of errors. Construction is the only place that can catch it.
    """

    def test_magic_key_is_checked(self):
        staged = identity_regs()
        mgckey = min(staged) # MGCKEY is the lowest of the four

        with self.assertRaises(RuntimeError):
            raw_driver(FakeWrapper({**staged, mgckey: 0xdeadbeef}))

    def test_nonsense_geometry_is_rejected(self):
        # Both are asserted at elaboration in the HDL, so a core reporting
        # either of these is not one, and the map derived from it would put the
        # sample buffer at an address that means nothing.
        for label, staged in (("probe width 0", identity_regs(0)),
                              ("depth 1", identity_regs(depth=1))):
            with self.subTest(label), self.assertRaises(RuntimeError):
                raw_driver(FakeWrapper(staged))

    def test_matching_build_comes_up(self):
        ila = raw_driver(FakeWrapper(identity_regs(67)))

        # everything the driver needs comes off the wire, nothing is passed in
        self.assertEqual(ila.probe_width, 67)
        self.assertEqual(ila.samp_buff_depth, _DEPTH)
        self.assertEqual(ila.samp_freq_hz, _FREQ_HZ)

class TestControl(unittest.TestCase):
    """
    TestControl: The control path, against LIBRE_ILA_get_status, LIBRE_ILA_arm,
    LIBRE_ILA_force_trigger and LIBRE_ILA_set_trigger_position in
    drivers/baremetal/core_libre_ila.c.
    """

    ARMED = 0x1
    TRIGD = 0x2
    DONE  = 0x4

    def _ila(self, status=0, depth=_DEPTH):
        wrapper = FakeWrapper()
        ila     = make_driver(wrapper, _PROBE_WIDTH, depth)

        wrapper.mem[ila.LIBRE_ILA_REGS_STATUS_REG_OFFSET] = status

        return wrapper, ila

    def test_status_decodes_latest_state_first(self):
        # the bits are sticky on the way up, so DONE outranks TRIGD outranks
        # ARMED. STATE in bits 4:3 is not CDCed and must not be decoded.
        for status, expected in ((0, 0),
                                 (self.ARMED, 1),
                                 (self.ARMED | self.TRIGD, 2),
                                 (self.ARMED | self.TRIGD | self.DONE, 3),
                                 (self.DONE, 3),
                                 (0x18, 0)):
            with self.subTest(status=status):
                _, ila = self._ila(status)

                self.assertEqual(ila.get_status(), expected)

    def test_arm_writes_arm_ft(self):
        wrapper, ila = self._ila(0)

        ila.arm()

        self.assertIn(ila.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET, wrapper.mem)

    def test_arm_refuses_when_already_armed(self):
        """A second write to ARM_FT forces a trigger, it does not re-arm."""
        wrapper, ila = self._ila(self.ARMED)

        with self.assertRaises(RuntimeError):
            ila.arm()

        self.assertNotIn(ila.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET, wrapper.mem)

    def test_force_trigger_refuses_when_not_armed(self):
        """The same write would arm the ILA instead of triggering it."""
        wrapper, ila = self._ila(0)

        with self.assertRaises(RuntimeError):
            ila.force_trigger()

        self.assertNotIn(ila.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET, wrapper.mem)

    def test_force_trigger_writes_arm_ft_when_armed(self):
        wrapper, ila = self._ila(self.ARMED)

        ila.force_trigger()

        self.assertIn(ila.LIBRE_ILA_REGS_ARM_FT_REG_OFFSET, wrapper.mem)

    def test_wait_done_returns_on_done(self):
        _, ila = self._ila(self.ARMED | self.TRIGD | self.DONE)

        self.assertIsNone(ila.wait_done(0))

    def test_wait_done_raises_on_timeout(self):
        _, ila = self._ila(self.ARMED)

        with self.assertRaises(TimeoutError):
            ila.wait_done(0)

    def test_trigger_position_has_to_sit_in_the_window(self):
        wrapper, ila = self._ila(0, 2048)

        ila.set_trigger_position(2047)
        self.assertEqual(wrapper.mem[ila.LIBRE_ILA_REGS_TRIG_POS_REG_OFFSET], 2047)

        for position in (2048, -1):
            with self.subTest(position=position), self.assertRaises(ValueError):
                ila.set_trigger_position(position)

    def test_configure_trigger_writes_the_whole_stride(self):
        wrapper, ila = self._ila(0)
        cond         = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
        mask         = [0x0000000f, 0, 0, 0]

        ila.configure_trigger(cond, mask, 1)

        for i in range(ila.stride_width):
            self.assertEqual(wrapper.mem[ila.LIBRE_ILA_REGS_TRIG_COND_REG_OFFSET + 4 * i], cond[i])
            self.assertEqual(wrapper.mem[ila.LIBRE_ILA_REGS_TRIG_MASK_REG_OFFSET + 4 * i], mask[i])

        self.assertEqual(wrapper.mem[ila.LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET], 1)
        # the reserved input register sits between TRIG_CFG and the vector
        self.assertNotIn(ila.LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET + 4, wrapper.mem)

    def test_configure_trigger_checks_its_arguments(self):
        _, ila = self._ila(0)
        full   = [0] * ila.stride_width

        # a short vector would leave the top of the trigger holding whatever
        # was there before. mode 8 is a bit above the three TRIG_CFG defines,
        # and mode 4 is FALLING without EDGE, which the core would silently
        # read as a plain level trigger.
        for cond, mask, mode in ((full[:-1], full, 0),
                                 (full, full[:-1], 0),
                                 (full, full, 8),
                                 (full, full, 4),
                                 (full, full, -1)):
            with self.subTest(mode=mode, n_cond=len(cond), n_mask=len(mask)):
                with self.assertRaises(ValueError):
                    ila.configure_trigger(cond, mask, mode)

    def test_configure_trigger_accepts_the_edge_modes(self):
        """
        The edge flags OR onto the reduction, so every combination of the three
        TRIG_CFG bits that means something has to reach the register intact.
        """
        full = [0] * 4

        for mode in (0, 1, 2, 3, 6, 7):
            with self.subTest(mode=mode):
                wrapper, ila = self._ila(0)
                ila.configure_trigger(full, full, mode)
                self.assertEqual(wrapper.mem[ila.LIBRE_ILA_REGS_TRIG_CFG_REG_OFFSET], mode)

class TestReadout(unittest.TestCase):
    """
    TestReadout: The circular buffer is unrolled from the oldest sample and the
    trigger index rebased onto that ordering, as LIBRE_ILA_read_data does.
    """

    def _staged(self, depth=8, probe_width=67, frst_idx=5, trig_idx=7):
        """
        _staged: A wrapper holding a filled sample buffer and both indices.

        depth: The sample buffer depth, a power of two.
        probe_width: The probe width, sets the lane count and the stride.
        frst_idx: The buffer index of the oldest sample.
        trig_idx: The buffer index of the trigger sample.

        returns: (wrapper, ila).
        """

        wrapper = FakeWrapper()
        ila     = make_driver(wrapper, probe_width, depth)

        wrapper.mem[ila.LIBRE_ILA_REGS_SAMP_BUFF_FRST_IDX_REG_OFFSET] = frst_idx
        wrapper.mem[ila.LIBRE_ILA_REGS_SAMP_BUFF_TRIG_IDX_REG_OFFSET] = trig_idx

        # row n gets 0x1000n, 0x2000n, 0x3000n and then padding up to the stride
        for row in range(depth):
            for lane in range(ila.stride_width):
                word = ((lane + 1) << 12 | row) if lane < ila.n_lanes else 0xdeadbeef

                wrapper.mem[ila.LIBRE_ILA_REGS_SAMP_BUFF_BASE_REG_OFFSET
                            + 4 * (row * ila.stride_width + lane)] = word

        return wrapper, ila

    def test_read_idx_returns_oldest_then_trigger(self):
        _, ila = self._staged(frst_idx=5, trig_idx=7)

        self.assertEqual(ila.read_idx(), [5, 7])

    def test_samples_come_out_oldest_first(self):
        _, ila           = self._staged(depth=8, frst_idx=5, trig_idx=7)
        samples, trg_idx = ila.read_data()

        # the readback starts at row 5 and wraps: 5 6 7 0 1 2 3 4
        self.assertEqual(len(samples), 8)
        self.assertEqual([s[0] & 0xff for s in samples], [5, 6, 7, 0, 1, 2, 3, 4])

        # the trigger sat at row 7, three rows into that ordering
        self.assertEqual(trg_idx, 2)
        self.assertEqual(samples[trg_idx][0] & 0xff, 7)

    def test_padding_above_the_lanes_is_dropped(self):
        _, ila      = self._staged()
        samples, _  = ila.read_data()

        # 67 bits is 3 lanes on a stride of 4, the fourth register is padding
        self.assertTrue(all(len(s) == ila.n_lanes for s in samples))
        self.assertEqual(samples[0], [0x1005, 0x2005, 0x3005])

    def test_unwrapped_buffer_is_left_alone(self):
        _, ila           = self._staged(depth=8, frst_idx=0, trig_idx=3)
        samples, trg_idx = ila.read_data()

        self.assertEqual([s[0] & 0xff for s in samples], list(range(8)))
        self.assertEqual(trg_idx, 3)

if __name__ == "__main__":
    unittest.main(verbosity=2)