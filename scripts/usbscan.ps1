param([switch]$Listen, [int]$Seconds = 60)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class UsbScan {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, int inl, byte[] outb, int outl, out int ret, IntPtr ov);
    // CTL_CODE(FILE_DEVICE_USB_SCAN=0x8000, 0x800+n, METHOD_BUFFERED, FILE_ANY_ACCESS)
    public static uint Ioctl(int n) { return (uint)((0x8000 << 16) | ((0x800 + n) << 2)); }
}
"@
$ErrorActionPreference = 'Stop'
$h = [UsbScan]::CreateFile('\\.\Usbscan0', [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($h.IsInvalid) { throw "open failed, Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }

# IOCTL_GET_DEVICE_DESCRIPTOR (index 6): USHORT VendorId, ProductId, BcdDevice, LanguageId
$b = New-Object byte[] 8; $r = 0
if ([UsbScan]::DeviceIoControl($h, [UsbScan]::Ioctl(6), $null, 0, $b, 8, [ref]$r, [IntPtr]::Zero)) {
    "Device: VID {0:X4} PID {1:X4} bcd {2:X4}" -f [BitConverter]::ToUInt16($b,0), [BitConverter]::ToUInt16($b,2), [BitConverter]::ToUInt16($b,4)
}

# IOCTL_GET_PIPE_CONFIGURATION (index 10): ULONG count; then 8x {USHORT maxPkt; UCHAR ep; UCHAR interval; ULONG type}
$b = New-Object byte[] (4 + 8*8)
if (-not [UsbScan]::DeviceIoControl($h, [UsbScan]::Ioctl(10), $null, 0, $b, $b.Length, [ref]$r, [IntPtr]::Zero)) {
    throw "GET_PIPE_CONFIGURATION failed, Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
$types = 'Control','Isochronous','Bulk','Interrupt'
$n = [BitConverter]::ToUInt32($b, 0)
"Pipes: $n"
for ($i = 0; $i -lt $n; $i++) {
    $o = 4 + 8*$i
    $ep = $b[$o+2]
    "  EP 0x{0:X2} ({1,-3}) {2,-9} maxPacket={3} interval={4}" -f $ep, $(if ($ep -band 0x80) {'IN'} else {'OUT'}), $types[[BitConverter]::ToUInt32($b,$o+4)], [BitConverter]::ToUInt16($b,$o), $b[$o+3]
}

if ($Listen) {
    # IOCTL_WAIT_ON_DEVICE_EVENT (index 8): blocks until the interrupt IN pipe delivers data
    "Waiting for interrupt data - press the Scan button on the printer (Ctrl+C to stop)..."
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $b = New-Object byte[] 64
        if ([UsbScan]::DeviceIoControl($h, [UsbScan]::Ioctl(8), $null, 0, $b, $b.Length, [ref]$r, [IntPtr]::Zero)) {
            "{0:HH:mm:ss.fff}  {1} bytes: {2}" -f (Get-Date), $r, (($b[0..([Math]::Max($r,1)-1)] | % { $_.ToString('X2') }) -join ' ')
        } else {
            "WAIT_ON_DEVICE_EVENT failed, Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; break
        }
    }
}
$h.Close()
