#!/usr/bin/env python3
"""Scan-to-PC button daemon for the Samsung SCX-4500 (USB 04e8:3426).

Protocol (reverse-engineered from Samsung Scan2Pc, see ../NOTES.md):
  1. Register: bulk OUT on the printer interface (1, EP 0x01) a 941-byte block listing the
     destinations shown on the panel; the printer acks with 12 bytes on EP 0x82.
  2. Poll: vendor control IN  bmRequestType=0xC1 bRequest=0x0C wValue=0x0087 wIndex=0x0100 len 8.
     All zeros = nothing pending; non-zero (seen: 21 09 02 01 00 00 00 00) = button pressed.
     The event is cleared by reading it.
On an event the hook script is run with SCX_EVENT (hex) and SCX_DEST (destination number) set.

Requires: python3-usb (pyusb). Usage: scx4500-buttond.py [--hook /path/to/hook] [-v]
"""
import argparse
import logging
import os
import subprocess
import time

import usb.core
import usb.util

VID, PID = 0x04E8, 0x3426
PRINTER_IFACE = 1
EP_OUT, EP_IN = 0x01, 0x82

# Header 1B A4 00 00, big-endian payload length, 5 bytes host id (as sent by Scan2Pc),
# destination count, then the destination name(s), zero-padded to 941 bytes.
REGISTRATION = (bytes.fromhex('1ba4000003a750e082c24401') + b'My Documents').ljust(941, b'\0')
POLL = dict(bmRequestType=0xC1, bRequest=0x0C, wValue=0x0087, wIndex=0x0100, data_or_wLength=8)

log = logging.getLogger('scx4500')


def find_device():
    return usb.core.find(idVendor=VID, idProduct=PID)


def register(dev):
    """Send the destination list on the printer interface, then hand the interface back."""
    reattach = False
    try:
        if dev.is_kernel_driver_active(PRINTER_IFACE):  # usblp
            dev.detach_kernel_driver(PRINTER_IFACE)
            reattach = True
        usb.util.claim_interface(dev, PRINTER_IFACE)
        dev.write(EP_OUT, REGISTRATION, timeout=3000)
        ack = bytes(dev.read(EP_IN, 64, timeout=3000))
        log.info('registered, ack %s', ack.hex(' '))
        return ack[:4] == b'\x1b\xa4\x00\x00' and ack[-1:] == b'\x00'
    finally:
        usb.util.release_interface(dev, PRINTER_IFACE)
        if reattach:
            try:
                dev.attach_kernel_driver(PRINTER_IFACE)
            except usb.core.USBError as e:
                log.warning('could not reattach usblp: %s', e)


def poll(dev):
    return bytes(dev.ctrl_transfer(timeout=2000, **POLL))


def run_hook(hook, event):
    env = dict(os.environ, SCX_EVENT=event.hex(), SCX_DEST=str(event[3]))
    log.info('button pressed (%s), running %s', event.hex(' '), hook)
    result = subprocess.run([hook], env=env)  # blocks: no polling while scanning
    log.info('hook finished with exit code %d', result.returncode)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--hook', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scan-hook.sh'))
    ap.add_argument('--interval', type=float, default=1.0, help='poll interval in seconds')
    ap.add_argument('--reregister', type=float, default=600, help='re-send registration every N seconds')
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format='%(asctime)s %(levelname)s %(message)s')

    dev, registered_at = None, 0.0
    while True:
        try:
            if dev is None:
                dev = find_device()
                if dev is None:
                    time.sleep(5)
                    continue
                log.info('found SCX-4500 on bus %d address %d', dev.bus, dev.address)
                registered_at = 0.0
            if time.monotonic() - registered_at > args.reregister:
                if register(dev):
                    registered_at = time.monotonic()
            event = poll(dev)
            log.debug('poll %s', event.hex(' '))
            if any(event):
                run_hook(args.hook, event)
        except usb.core.USBError as e:
            if e.errno == 19 or e.backend_error_code == -4:  # ENODEV / LIBUSB_ERROR_NO_DEVICE
                log.warning('printer disconnected')
                dev = None
            else:  # e.g. EBUSY while CUPS holds the printer interface: retry next round
                log.warning('USB error: %s', e)
        time.sleep(args.interval)


if __name__ == '__main__':
    main()
