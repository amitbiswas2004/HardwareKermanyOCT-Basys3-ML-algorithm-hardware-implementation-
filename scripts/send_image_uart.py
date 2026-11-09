#!/usr/bin/env python3
"""Send one rtl_ok testbench .mem image to the Basys 3 USB-UART port.

Install pyserial: python -m pip install pyserial
Usage: python scripts/send_image_uart.py simulation/testbench_vectors/tb_img_CNV_expected_CNV.mem COM5
"""
from pathlib import Path
import argparse
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image_mem", type=Path, help="16,384-line hexadecimal pixel .mem file")
    parser.add_argument("port", help="serial port, e.g. COM5 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    tokens = args.image_mem.read_text(encoding="ascii").split()
    if len(tokens) != 128 * 128:
        raise ValueError(f"Expected 16,384 pixels; found {len(tokens)}")
    values = [int(token, 16) for token in tokens]
    if any(value < 0 or value > 255 for value in values):
        raise ValueError("Every pixel must fit in one byte")
    payload = bytes(values)

    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required: python -m pip install pyserial") from exc

    with serial.Serial(args.port, args.baud, bytesize=8, parity="N", stopbits=1, timeout=2) as ser:
        time.sleep(0.2)
        ser.write(payload)
        ser.flush()
    print(f"Sent {len(payload)} pixels ({len(payload)} bytes) to {args.port} at {args.baud} baud.")
    print("Wait for LED[2] to turn on. LED[1:0] shows the predicted class.")


if __name__ == "__main__":
    main()
