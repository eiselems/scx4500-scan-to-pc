"""Summarize a USBPcap capture of the SCX-4500: pair control setups with their responses and
print every distinct (request, response) with first/last time seen and count; bulk transfers are
listed individually. Usage: python pcap_summary.py <file.pcap>"""
import struct
import sys


def packets(path):
    with open(path, 'rb') as f:
        data = f.read()
    off = 24  # pcap global header
    t0 = None
    while off + 16 <= len(data):
        sec, usec, incl, _ = struct.unpack_from('<IIII', data, off)
        off += 16
        pkt = data[off:off + incl]
        off += incl
        t = sec + usec / 1e6
        t0 = t if t0 is None else t0
        yield t - t0, pkt


def parse(pkt):
    # USBPCAP_BUFFER_PACKET_HEADER
    hlen, irp, status, func, info, bus, dev, ep, xfer, dlen = struct.unpack_from('<HQIHBHHBBI', pkt, 0)
    d = {'info': info, 'dev': dev, 'ep': ep, 'xfer': xfer, 'payload': pkt[hlen:hlen + dlen]}
    if xfer == 2 and hlen >= 28:
        d['stage'] = pkt[27]  # 0 = setup, 1 = data, 2 = status, 3 = complete
    return d


def main(path):
    seen = {}       # (setup, response) -> [first, last, count]
    order = []
    pending = None  # setup bytes waiting for their response
    for t, raw in packets(path):
        p = parse(raw)
        if p['xfer'] == 2:  # control
            if p.get('stage') == 0:
                pending = p['payload'][:8]
            elif pending is not None and p['info'] & 1:  # response from device
                key = (pending.hex(' '), p['payload'].hex(' '))
                if key not in seen:
                    seen[key] = [t, t, 0]
                    order.append(key)
                seen[key][1] = t
                seen[key][2] += 1
                pending = None
        elif p['xfer'] == 3 and p['payload']:  # bulk with data
            direction = 'IN ' if p['info'] & 1 else 'OUT'
            pl = p['payload']
            print(f'{t:9.3f}  BULK {direction} ep{p["ep"] & 0x7f} {len(pl):4d}B  {pl[:48].hex(" ")}{" ..." if len(pl) > 48 else ""}')
    print('\nDistinct control request/response pairs:')
    for key in order:
        first, last, n = seen[key]
        setup, resp = key
        text = bytes.fromhex(resp.replace(' ', ''))
        shown = text[2:].decode('ascii', 'replace') if setup.startswith('a1 00') else resp
        print(f'  {first:9.3f}..{last:9.3f}  x{n:<4d} setup[{setup}]\n      -> {shown}')


if __name__ == '__main__':
    main(sys.argv[1])
