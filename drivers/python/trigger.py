#####################################################################
# File: trigger.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-05 Wed 09:41
# Last Modified: 2026-08-05 Wed 09:59
#
# Description: Per signal trigger patterns
#   This file contains the logic for parsing trigger patterns for individual signals.
#   It is helpful for converting radixes and dont cares.
#   Example: 0b0010_1xxx, 0xdead, 0d1234, -1234
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

# What a pattern may be written in. bin and hex carry don't cares, the two
# numeric ones do not, see the note on DONT_CARE below.
RADICES = ["bin", "hex", "uint", "int"]

DEFAULT_RADIX = "bin"

# Bits per digit, which is what makes an X in a hex pattern mean four don't
# cares and an X in a binary one mean a single bit.
_RADIX_BITS = {
    "bin": 1,
    "hex": 4
}

_RADIX_PREFIX = {
    "bin": "0b",
    "hex": "0x"
}

_RADIX_DIGITS = {
    "bin": "01",
    "hex": "0123456789abcdef"
}

# Accepted in a pattern for a bit nobody cares about. Upper case too, and '-'
# because that is what a truth table uses and someone will type it.
DONT_CARE = "xX-"

# A signal every bit of which is a don't care. Written out rather than left
# blank so a row of the conditions table says what it means.
ANY = "X"


def _clean(text):
    """
    _clean: Strip the decoration a pattern is allowed to carry.

    text: The pattern as typed.

    returns: The pattern with whitespace and underscores removed.
    """

    # Underscores group digits the way python's own literals allow, and someone
    # reading 0b0010_1xxx off a datasheet will type it that way
    return "".join(text.split()).replace("_", "")


def parse_pattern(text, width, radix=DEFAULT_RADIX):
    """
    parse_pattern: Turn one signal's pattern into the two halves of a trigger.

    text: The pattern. X, x or - is a don't care, in bin and hex only. An empty
        pattern, or one that is all don't cares, matches anything.
    width: The signal's width in bits.
    radix: What to read it in when the text carries no 0b/0x/0d prefix. The
        conditions table has a radix per row, so the row says what its own
        contents mean; a prefix in the text overrides it, since someone pasting
        0xdead into a binary row means hex and not an error.

    returns: (value, mask), both right aligned in the signal's own width. A
    mask bit set means the core compares that bit.
    """

    if width < 1:
        raise ValueError(f"a signal cannot be {width} bits wide")

    if radix not in RADICES:
        raise ValueError(f"'{radix}' is not one of {', '.join(RADICES)}")

    cleaned = _clean(text)

    limit = (1 << width) - 1

    # Nothing typed is the same as a row of X, which is what an untouched
    # conditions table is full of
    if not cleaned:
        return 0, 0

    # A pattern that is nothing but don't cares says the signal is not compared
    # at all, and every radix can say that much: it is mask zero. This is what
    # format_pattern writes as ANY whatever radix a row is in, so accepting it
    # here in every radix is what closes the round trip. Only a don't care mixed
    # in among digits needs one whose digits are worth whole bits, which is the
    # refusal further down.
    if all(character in DONT_CARE for character in cleaned):
        return 0, 0

    radix, digits = _split_prefix(cleaned, radix)

    if radix in _RADIX_BITS:
        return _parse_digits(digits, radix, width, text)

    # A leading minus is the sign here and a don't care in bin and hex, so the
    # two meanings never meet: this branch is only reached for uint and int.
    signless = digits.removeprefix("-")

    # uint and int have no digit that stands for a don't care: a decimal digit
    # is worth log2(10) bits, so there is no run of bits an 'X' could name. A
    # pattern in one of them therefore compares every bit of the signal, and a
    # user who wants otherwise writes it in bin or hex.
    if any(character in DONT_CARE for character in signless):
        raise ValueError(f"'{text}' puts a don't care in a {radix} pattern. Only bin and hex "
                         f"have a digit worth a whole number of bits, so write it as 0b or 0x.")

    try:
        value = int(digits, 10)
    except ValueError:
        raise ValueError(f"'{text}' is not a {radix} number")

    if radix == "int":
        # Two's complement in the signal's own width, so -1 on a 4 bit signal
        # is the 1111 the core will actually see
        if value < -(1 << (width - 1)) or value > (1 << (width - 1)) - 1:
            raise ValueError(f"'{text}' does not fit in {width} signed bits")

        value &= limit
    else:
        if value < 0:
            raise ValueError(f"'{text}' is negative. Write a signed value as int, not uint.")

        if value > limit:
            raise ValueError(f"'{text}' does not fit in {width} bits")

    return value, limit


def _split_prefix(cleaned, default):
    """
    _split_prefix: Work out what base a cleaned pattern is written in.

    cleaned: The pattern, decoration already removed.
    default: The radix to use when it carries no prefix.

    returns: (radix, digits).
    """

    lowered = cleaned.lower()

    for prefix, radix in (("0b", "bin"), ("0x", "hex"), ("0d", "uint")):
        if lowered.startswith(prefix):
            return radix, cleaned[len(prefix):]

    return default, cleaned


def _parse_digits(digits, radix, width, text):
    """
    _parse_digits: Read a bin or hex pattern, don't cares included.

    digits: The digits, prefix already removed.
    radix: "bin" or "hex".
    width: The signal's width in bits.
    text: The pattern as typed, for the error messages.

    returns: (value, mask).
    """

    if not digits:
        raise ValueError(f"'{text}' has a base but no digits")

    per_digit = _RADIX_BITS[radix]
    allowed   = _RADIX_DIGITS[radix]

    value = 0
    mask  = 0

    # Written MSB first, the way it is read, so each digit shifts what came
    # before it up out of the way
    for digit in digits:
        value <<= per_digit
        mask  <<= per_digit

        if digit in DONT_CARE:
            continue

        lowered = digit.lower()

        if lowered not in allowed:
            raise ValueError(f"'{text}' has '{digit}' in it, which is not a {radix} digit "
                             f"or a don't care")

        value |= int(lowered, 16 if radix == "hex" else 2)
        mask  |= (1 << per_digit) - 1

    # A hex pattern reaches a multiple of four bits, so the top digit of an odd
    # width signal may only be partly real. Bits above the signal are refused
    # rather than trimmed, since a pattern that does not fit is a mistake worth
    # naming and the core would compare the padding.
    if (value | mask) >> width:
        raise ValueError(f"'{text}' is wider than the {width} bit signal it is set on")

    return value, mask


def format_pattern(value, mask, width, radix=DEFAULT_RADIX):
    """
    format_pattern: Write one signal's condition and mask back out as a pattern.

    value: The condition bits, right aligned in the signal's width.
    mask: Which of them the core compares.
    width: The signal's width in bits.
    radix: One of RADICES.

    returns: The pattern, round tripping through parse_pattern.
    """

    if radix not in RADICES:
        raise ValueError(f"'{radix}' is not one of {', '.join(RADICES)}")

    limit = (1 << width) - 1

    value &= limit
    mask  &= limit

    # Nothing compared is a signal the trigger ignores, which reads better as
    # one X than as a row of them
    if mask == 0:
        return ANY

    if radix in _RADIX_BITS:
        per_digit = _RADIX_BITS[radix]

        # Rounded up, so a 67 bit probe's odd top bits still get a digit
        count = (width + per_digit - 1) // per_digit

        digits = ""

        for index in reversed(range(count)):
            shift      = index * per_digit
            digit_mask = ((1 << per_digit) - 1)

            if (mask >> shift) & digit_mask == digit_mask:
                digits += format((value >> shift) & digit_mask,
                                 "b" if radix == "bin" else "x")
            elif (mask >> shift) & digit_mask == 0:
                digits += ANY
            else:
                # Only reachable in hex, where one digit spans four bits and the
                # mask can split them. Falling back to binary keeps the value
                # exact rather than rounding the mask to fit the radix.
                return format_pattern(value, mask, width, "bin")

        return _RADIX_PREFIX[radix] + digits

    # uint and int cannot say "some bits", so a partial mask has to be shown in
    # a radix that can. The alternative would be printing a number that does not
    # describe the trigger the core is holding.
    if mask != limit:
        return format_pattern(value, mask, width, "bin")

    if radix == "int" and width > 0 and value >> (width - 1):
        return str(value - (1 << width))

    return str(value)


def patterns_to_vector(patterns, probes, radices=None):
    """
    patterns_to_vector: Assemble the whole probe word from per signal patterns.

    patterns: {signal name: pattern}. A name missing from it is left as a don't
        care, so a table only has to carry the rows someone has filled in.
    probes: The probe list vcd.load_portmap produced.
    radices: {signal name: radix} for the rows that are not in DEFAULT_RADIX,
        matching vector_to_patterns so a table round trips through the core
        without a row changing base under the user.

    returns: (condition, mask), covering the whole probe word, in the form
    session.Session.set_trigger takes.
    """

    radices = radices or {}

    known = {probe["name"] for probe in probes}

    for name in patterns:
        if name not in known:
            raise ValueError(f"'{name}' is not a signal in the portmap")

    condition = 0
    mask      = 0

    for probe in probes:
        text = patterns.get(probe["name"], "")

        try:
            value, bits = parse_pattern(text, probe["width"],
                                        radices.get(probe["name"], DEFAULT_RADIX))
        except ValueError as err:
            # Named, because a table of twenty rows and one message saying
            # "does not fit" would send the user looking through all of them
            raise ValueError(f"{probe['name']}: {err}")

        condition |= value << probe["lsb"]
        mask      |= bits  << probe["lsb"]

    return condition, mask


def vector_to_patterns(condition, mask, probes, radices=None):
    """
    vector_to_patterns: Split a whole probe word back into per signal patterns.

    condition: The condition the core is holding.
    mask: The mask the core is holding.
    probes: The probe list vcd.load_portmap produced.
    radices: {signal name: radix} for the rows that are not in DEFAULT_RADIX,
        so reading the core back does not reset how a row is being displayed.

    returns: {signal name: pattern}, one entry per probe.
    """

    radices  = radices or {}
    patterns = {}

    for probe in probes:
        width = probe["width"]
        limit = (1 << width) - 1

        patterns[probe["name"]] = format_pattern((condition >> probe["lsb"]) & limit,
                                                 (mask >> probe["lsb"]) & limit,
                                                 width,
                                                 radices.get(probe["name"], DEFAULT_RADIX))

    return patterns
