# Progress

## Done
- Identified the USB layout of the SCX-4500 (`04e8:3426`): interface 0 = scanner (bulk `0x03`/`0x84`,
  no interrupt endpoint), interface 1 = printer (bulk `0x01`/`0x82`).
- Found the Samsung component that handles the panel button: *Scan2Pc* (`scantopc.dll`) inside the Windows
  SmartPanel package, and got it running without the (blocked) installer.
- Captured Scan2Pc with USBPcap and decoded the protocol (see [README](README.md)):
  - registration block on the printer interface (reproduced byte for byte),
  - once-per-second vendor poll `C1 0C 0087 0100 len 8`,
  - button press → `21 09 02 01 00 00 00 00`, reported once, cleared on read,
  - a press without a polling host is lost.
- Wrote a pyusb daemon, hook script, udev rule and systemd unit in `linux/`.
- **Tested on Linux (2026-11-14):** registration ack matches Windows byte for byte, 3 presses → 3 events → 3 hook
  runs. Fixed a bug where the daemon never registered during the first 10 minutes after boot
  (`registered_at = 0.0` vs. `time.monotonic()` counting from boot), i.e. exactly when started as a service.

## Open questions
1. ~~**Linux access:** does usbfs allow the vendor control request while `usblp` is bound to interface 1?~~
   **Answered: yes.** Polling works with `usblp` bound; detach/reattach around the registration works.
2. **Event bytes:** only one sample so far (`21 09 02 01`). Do the middle bytes change with panel settings
   (colour, resolution, …)?
3. **Multiple destinations:** layout of the registration block for more than one name (941 bytes for one).
4. **Host id and lifetime:** do the 5 host-id bytes matter, and how long does the printer keep a registration?
   The daemon re-registers every 10 minutes to be safe. Observed: a registration survives a replug / host
   switch (a press was reported on Linux before the daemon had registered).
5. **Scanning:** does SANE `xerox_mfp` scan this model? `scanimage -L` lists it via `xerox_mfp` and
   Samsung's `smfp`; an actual scan from the hook is not tested yet.

Points 2–4 can be worked out on Linux with `scx4500-buttond.py -v`, which logs every poll reply.

## Next steps
- [x] On the Linux box: `scanimage -L`, then a foreground run of `scx4500-buttond.py -v` (questions 1 and 5).
- [x] Install the systemd user service with the `open-skanpage.sh` hook – button opens Skanpage (tested 2026-11-14).
- [ ] Run a real scan from `scan-hook.sh`.
- [ ] Workflow-picker popup as the hook (choose: Skanpage, scan to folder, scan to mail, …).
- [ ] Press with different panel settings and log the events (question 2).
- [ ] Experiment with the registration block: two names, different host id (questions 3 and 4).
- [ ] Fix the Windows `poll_button.ps1` (usbscan `IO_BLOCK_EX` request-type encoding) – optional.

## Ideas for what to build on top
**Ready almost as-is (only the hook changes):**
- One-button scan to a folder (current `scan-hook.sh`).
- Scan → `ocrmypdf` → searchable PDF.
- Drop scans into the consume folder of **Paperless-ngx**.
- Upload to a NAS / Nextcloud / cloud drive via `rclone` or `scp`.
- Notifications: `notify-send`, ntfy, Telegram or e-mail with the scan attached.

**Slightly more work:**
- Multi-page documents: each press adds a page, a timeout assembles them into one PDF.
- Use the button as a general-purpose hardware trigger (Home Assistant webhook, backup, any script).
- Run the daemon on a Raspberry Pi / home server the printer is plugged into, so it works without a PC.

**Needs the open experiments:**
- Several destinations on the panel ("Paperless", "E-mail", "Folder") mapped to different hooks (question 3).
- Use panel settings from the event bytes (question 2).

**Suggested first build:** Pi or home server running the daemon, hook = `scanimage` → `ocrmypdf` →
Paperless consume folder, plus an ntfy notification.
