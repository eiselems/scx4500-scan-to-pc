# Capture USB traffic of the Samsung SCX-4500 (VID 04E8 PID 3426) with USBPcap.
# Run from an elevated PowerShell. Ctrl+C stops the capture.
param([string]$Out = "$PSScriptRoot\..\captures\scx4500_$(Get-Date -f yyyyMMdd_HHmmss).pcap")
$cmd = 'C:\Program Files\USBPcap\USBPcapCMD.exe'
# USBPcapCMD writes its extcap output to the console in a way PowerShell can't pipe; go through cmd.
function Invoke-Extcap([string]$a) { cmd /c "`"$cmd`" $a 2>&1" }

# Find the USBPcap root hub that has the printer attached. The printer itself shows up as a generic
# "USB composite device"; its child entries carry the "Samsung SCX-4500" name and a {parent=N} tag.
$hubs = Invoke-Extcap '--extcap-interfaces' | Select-String 'value=(\\\\\.\\USBPcap\d+)' | % { $_.Matches[0].Groups[1].Value }
if (-not $hubs) { throw 'No USBPcap interfaces - reboot after installing USBPcap.' }
$hub = $null; $addr = $null
foreach ($h in $hubs) {
    $m = Invoke-Extcap "--extcap-interface $h --extcap-config" | Select-String 'display=Samsung SCX-4500.*\{parent=(\d+)\}' | Select -First 1
    if ($m) { $hub = $h; $addr = $m.Matches[0].Groups[1].Value; break }
}
if (-not $hub) { throw 'Printer not found on any USBPcap hub - is it switched on and connected?' }

$Out = [IO.Path]::GetFullPath($Out)
"Printer on $hub (device $addr). Writing $Out - press Ctrl+C to stop."
& $cmd -d $hub --devices $addr --inject-descriptors -o $Out
