# scx4500-scan-to-pc

Reverse-engineered **"Scan → PC" panel button protocol** of the Samsung SCX-4500 laser MFP (USB `04e8:3426`),
plus a small Linux daemon that reacts to the button – no Samsung software needed.

## How the button works

The printer never pushes anything: the scanner interface has no interrupt endpoint, and a button press
without a polling host produces no USB traffic and is not queued (the panel just shows an animation).
Samsung's *Scan2Pc* (part of the Windows SmartPanel / Printer Settings Utility) makes it work in two steps,
both on the **printer interface (interface 1)**, not the scanner interface:

### 1. Registration – tell the printer which destinations to offer
Bulk OUT on EP `0x01`, 941 bytes:

| Offset | Bytes | Meaning |
|---|---|---|
| 0 | `1B A4 00 00` | header |
| 4 | `03 A7` | big-endian length of the rest (935) |
| 6 | `50 E0 82 C2 44` | host id (value sent by Scan2Pc) |
| 11 | `01` | number of destinations |
| 12 | `"My Documents"` | destination name, zero-padded to 941 bytes total |

The printer acks on bulk IN EP `0x82` with `1B A4 00 00 00 06 50 E0 82 C2 44 00` (last byte `00` = OK).

### 2. Polling – ask once per second whether the button was pressed
Vendor control transfer, device-to-host:

```
bmRequestType = 0xC1  bRequest = 0x0C  wValue = 0x0087  wIndex = 0x0100  wLength = 8
```

(`wIndex` high byte = interface 1, the printer-class convention.)

| Reply | Meaning |
|---|---|
| `00 00 00 00 00 00 00 00` | nothing pending |
| `21 09 02 01 00 00 00 00` | **button pressed** – reported exactly once, reading clears it. The last byte is probably the destination number (1 = "My Documents"). |

Scan2Pc also polls the printer-class `GET_DEVICE_ID` (`A1 00 …`) for its status display
(`MFG:Samsung;CMD:GDI;MDL:SCX-4500 Series;CLS:PRINTER;MODE:PCL;STATUS:IDLE;` – the firmware repeats
the `MODE/STATUS` part a varying number of times). That isn't needed for the button.

The actual scan afterwards is ordinary scanning on interface 0 (SANE `xerox_mfp` on Linux).

## Linux daemon – `linux/`

| File | Purpose |
|---|---|
| `scx4500-buttond.py` | pyusb daemon: registers (briefly detaching `usblp` from interface 1), polls once per second, re-registers every 10 min and after replug, runs a hook on a button press |
| `open-skanpage.sh` | default hook (used by the service): opens Skanpage detached, or just notifies if it is already open |
| `scan-hook.sh` | alternative hook: `scanimage` → `~/Scans/scan_<timestamp>.png`; gets `SCX_EVENT` / `SCX_DEST` in the environment |
| `99-scx4500.rules` | udev rule: device accessible to group `scanner` |
| `scx4500-buttond.service` | systemd user unit, starts with the graphical session (expects the files in `~/scx4500/`, e.g. `ln -s <repo>/linux ~/scx4500`) |

```sh
sudo apt install python3-usb sane-utils           # or your distro's equivalents
mkdir -p ~/scx4500 && cp linux/scx4500-buttond.py linux/open-skanpage.sh linux/scan-hook.sh ~/scx4500/ && chmod +x ~/scx4500/*
sudo cp linux/99-scx4500.rules /etc/udev/rules.d/ && sudo udevadm control --reload   # then replug the printer
python3 ~/scx4500/scx4500-buttond.py -v            # try it in the foreground first
cp linux/scx4500-buttond.service ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now scx4500-buttond
```

**Status:** tested on real hardware (Arch Linux, kernel 7.2, pyusb 1.3.1, 2026-11-14): the daemon registers
(ack `1B A4 00 00 00 06 50 E0 82 C2 44 00`, identical to Windows), idle polls return all zeros, and three
button presses produced exactly three `21 09 02 01 00 00 00 00` events and three hook runs.
- The vendor poll works while `usblp` is bound to interface 1; detaching/reattaching `usblp` for the
  registration works too.
- A registration survives a replug / host switch: a press was reported before this host had registered.

Still open:
- How long does the printer keep a registration? (The daemon re-registers every 10 minutes.)
- Multiple destinations: changing the count byte / adding names should give a choice on the panel and
  change the last event byte.

See [progress.md](progress.md) for status, open questions and ideas.

## Evidence & tools

- `captures/scx4500_20261114_112404.pcap` – Scan2Pc start + two button presses (t = 30.7 s, 57.0 s)
- `captures/scx4500_20261114_112942.pcap` – press without Scan2Pc (no traffic), Scan2Pc start at 54.6 s, single press at 76.8 s
- `captures/registration_941.bin` – the registration block as sent by Scan2Pc
- `scripts/pcap_summary.py` – pairs control requests with responses and lists every distinct reply with time range
- `scripts/capture.ps1` – Windows: finds the printer's USBPcap hub and captures its traffic (run elevated)
- `scripts/decode.ps1` – Windows: dumps USB payloads with tshark
- `scripts/usbscan.ps1` – Windows: lists the scanner interface's pipes via `usbscan.sys`
- `scripts/poll_button.ps1` – Windows poller via `usbscan.sys` `IOCTL_SEND_USB_REQUEST` – **not working yet**
  (usbscan answers every request with the 1284 id prefix; the `IO_BLOCK_EX` request-type encoding is unclear)

### How the captures were made
Windows 11, USBPcap + Wireshark. Samsung's SmartPanel installer (`SCX-4500_SP.exe`, still on HP's FTP under
`pub/softlib/software13/printers/SS/SCX-4500/`) is blocked by Windows, so it was unpacked with 7-Zip and
`PSU/Data/Scan2Pc.exe` was run directly after copying `ssdevm.dll` / `ssusbpn.dll` from `PSU/Shared64/` next
to it. Scan2Pc then reacts to the button but fails at the actual scan (it needs the old TWAIN driver),
which doesn't matter for the protocol.

Samsung software is not included in this repository.
