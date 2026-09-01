## Sends replay transport commands to a running replay server: each
## char of the first CLI arg rides one sprite-protocol chat frame.
import std/os, whisky
let
  url = paramStr(1)
  commands = paramStr(2)
var socket = newWebSocket(url)
var packet = newSeq[uint8]()
packet.add(0x81'u8)
packet.add(uint8(commands.len and 0xff))
packet.add(uint8(commands.len shr 8))
for ch in commands:
  packet.add(uint8(ord(ch)))
var text = newString(packet.len)
for i, b in packet:
  text[i] = char(b)
socket.send(text, BinaryMessage)
sleep(500)
socket.close()
echo "sent ", commands.len, " commands"
