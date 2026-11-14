# Poll the SCX-4500 "Scan to PC" button state without any Samsung software.
# Sends the same vendor request Scan2Pc/scantopc.dll uses: bmRequestType C1, bRequest 0x0C,
# wValue 0x0087, wIndex 0x0100, 8 bytes - through usbscan.sys IOCTL_SEND_USB_REQUEST on \\.\Usbscan0.
# All-zero reply = nothing pending; anything else (seen: 21 09 02 01 00 00 00 00) = button event.
param([int]$Seconds = 120, [int]$IntervalMs = 1000)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class UsbScanReq {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool DeviceIoControl(SafeFileHandle h, uint code, ref IO_BLOCK_EX inb, int inl, byte[] outb, int outl, out int ret, IntPtr ov);
    // usbscan.h IO_BLOCK_EX
    [StructLayout(LayoutKind.Sequential)]
    public struct IO_BLOCK_EX {
        public uint uOffset;              // -> wValue
        public uint uLength;              // -> wLength
        public IntPtr pbyData;            // unused for METHOD_BUFFERED IN transfers
        public uint uIndex;               // -> wIndex
        public byte bRequest;
        public byte bmRequestType;
        public byte fTransferDirectionIn;
    }
    // CTL_CODE(FILE_DEVICE_USB_SCAN=0x8000, IOCTL_INDEX+9, METHOD_BUFFERED, FILE_ANY_ACCESS)
    public const uint IOCTL_SEND_USB_REQUEST = 0x80002024;
}
"@

$h = [UsbScanReq]::CreateFile('\\.\Usbscan0', [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($h.IsInvalid) { throw "open \\.\Usbscan0 failed, Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }

function Send-Request([byte]$type, [byte]$req, [uint32]$value, [uint32]$index, [uint32]$len) {
    $blk = New-Object UsbScanReq+IO_BLOCK_EX
    $blk.uOffset = $value; $blk.uLength = $len; $blk.uIndex = $index
    $blk.bRequest = $req; $blk.bmRequestType = $type; $blk.fTransferDirectionIn = 1
    $out = New-Object byte[] $len; $r = 0
    if (-not [UsbScanReq]::DeviceIoControl($h, [UsbScanReq]::IOCTL_SEND_USB_REQUEST, [ref]$blk,
            [Runtime.InteropServices.Marshal]::SizeOf($blk), $out, $len, [ref]$r, [IntPtr]::Zero)) {
        throw "IOCTL failed, Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    , $out[0..([Math]::Max($r,1)-1)]
}

"Polling every $IntervalMs ms for $Seconds s - press Scan -> PC on the printer..."
$deadline = (Get-Date).AddSeconds($Seconds); $last = $null
while ((Get-Date) -lt $deadline) {
    $hex = ((Send-Request 0xC1 0x0C 0x0087 0x0100 8) | ForEach-Object { $_.ToString('X2') }) -join ' '
    if ($hex -ne $last) { "{0:HH:mm:ss.fff}  {1}" -f (Get-Date), $hex; $last = $hex }
    Start-Sleep -Milliseconds $IntervalMs
}
$h.Close()
