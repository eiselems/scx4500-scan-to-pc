# Print every bulk/interrupt/control payload in a USBPcap capture as hex, one line per transfer.
param([Parameter(Mandatory)][string]$Pcap)
& 'C:\Program Files\Wireshark\tshark.exe' -r $Pcap -Y 'usb.capdata || usb.data_fragment' `
  -T fields -E separator=' | ' `
  -e frame.number -e frame.time_relative -e usb.src -e usb.dst -e usb.endpoint_address -e usb.transfer_type -e usb.capdata
