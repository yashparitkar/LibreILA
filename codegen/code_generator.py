#####################################################################
# File: code_generator.py
# Author: Y.U.P. (paritkary25)
# Created: 2026-07-24 Fri 19:48
# Last Modified: 2026-07-28 Tue 20:42
#
# Description: This script generates code with the user portmap and 
#   configuration.
#####################################################################

import argparse
import os
import sys

# Command line arguments ############################################
# --portmap <file>
# --config <file>
# if nothing is provided, the default portmap and configuration files will be used.
#
# The defaults are resolved relative to this script, not to the current
# working directory, so the script can be invoked from anywhere (e.g. from
# the project Makefile at the repository root). Paths given on the command
# line are resolved relative to the current working directory, as usual.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PORTMAP_FILE = os.path.join(SCRIPT_DIR, "templates", "default_portmap.csv")
DEFAULT_CONFIG_FILE = os.path.join(SCRIPT_DIR, "templates", "default_configuration.csv")

parser = argparse.ArgumentParser(
    description="Generate the LibreILA core from a portmap and a configuration."
)
parser.add_argument(
    "--portmap",
    metavar="<file>",
    default=DEFAULT_PORTMAP_FILE,
    help="probe portmap CSV (default: templates/default_portmap.csv)"
)
parser.add_argument(
    "--config",
    metavar="<file>",
    default=DEFAULT_CONFIG_FILE,
    help="core configuration CSV (default: templates/default_configuration.csv)"
)
args = parser.parse_args()

PORTMAP_FILE = args.portmap
CONFIG_FILE = args.config

for path in (CONFIG_FILE, PORTMAP_FILE):
    if not os.path.isfile(path):
        sys.exit(f"error: no such file: {path}")

print(f"Configuration file: {CONFIG_FILE}")
print(f"Portmap file: {PORTMAP_FILE}")


# Required keywords for the configuration file
required_keywords = [
    "G_SAMP_CLK_FREQ",
    "G_AXIL_CLK_FREQ",
    "G_EXTERNAL_TRIG",
    "G_SAMP_BUFF_DEPTH",
    "GEN_TYPE",
    "G_UART_RX_FIFO_DEPTH",
    "G_UART_TX_FIFO_DEPTH",
    "G_BAUD_RATE"
]

# Read the configuration file
with open(CONFIG_FILE, "r") as config_file:
    config_lines = config_file.readlines()

# Parse the configuration values and make a dictionary of them
for line in config_lines:
    if line.strip() and not line.startswith("#"):
        key, type_str, value_str = line.strip().split(",")
        if type_str == "integer":
            value = int(value_str)
        elif type_str == "natural":
            value = int(value_str)
            if value < 0:
                raise ValueError(f"Value for {key} must be a natural number.")
        elif type_str == "string":
            value = value_str
        else:
            raise ValueError(f"Unknown type '{type_str}' for key '{key}'.")

        globals()[key] = value

# Ensuring all required keywords are present
for keyword in required_keywords:
    if keyword not in globals():
        raise ValueError(f"Missing required configuration keyword: {keyword}")


# Checking the values ###############################################
if G_SAMP_CLK_FREQ <= 0:
    raise ValueError("Sampling clock frequency must be a positive integer.")

if G_AXIL_CLK_FREQ <= 0:
    raise ValueError("AXI-Lite clock frequency must be a positive integer.")

# FIFO depth should be a power of 2 and greater than 1
if G_UART_RX_FIFO_DEPTH <= 1 or (G_UART_RX_FIFO_DEPTH & (G_UART_RX_FIFO_DEPTH - 1)):
    raise ValueError("UART RX FIFO depth must be a power of 2 and greater than 1.")

if G_UART_TX_FIFO_DEPTH <= 1 or (G_UART_TX_FIFO_DEPTH & (G_UART_TX_FIFO_DEPTH - 1)):
    raise ValueError("UART TX FIFO depth must be a power of 2 and greater than 1.")

if G_SAMP_BUFF_DEPTH <= 1 or (G_SAMP_BUFF_DEPTH & (G_SAMP_BUFF_DEPTH - 1)):
    raise ValueError("Sample buffer depth must be a power of 2 and greater than 1.")

# 0 < baud rate < samp_clk/32(Warning) < samp_clk/16(Error)
if G_BAUD_RATE <= 0:
    raise ValueError("Baud rate must be a positive integer.")
else:
    if G_BAUD_RATE >= G_AXIL_CLK_FREQ / 16:
        raise ValueError("Baud rate must be less than axil_ckl_freq/16.")
    elif G_BAUD_RATE >= G_AXIL_CLK_FREQ / 32:
        print("Warning: Baud rate is greater than axil_ckl_freq/32. This may cause issues.")

# Read back the configuration values for verification
for var_name, var_value in [
    ("G_SAMP_CLK_FREQ", G_SAMP_CLK_FREQ),
    ("G_AXIL_CLK_FREQ", G_AXIL_CLK_FREQ),
    ("G_EXTERNAL_TRIG", G_EXTERNAL_TRIG),
    ("G_SAMP_BUFF_DEPTH", G_SAMP_BUFF_DEPTH),
    ("G_UART_RX_FIFO_DEPTH", G_UART_RX_FIFO_DEPTH),
    ("G_UART_TX_FIFO_DEPTH", G_UART_TX_FIFO_DEPTH),
    ("G_BAUD_RATE", G_BAUD_RATE)
]:
    print(f"{var_name}: {var_value}")

# Read the user portmap file
with open(PORTMAP_FILE, "r") as portmap_file:
    portmap_lines = portmap_file.readlines()
