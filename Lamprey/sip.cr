require "socket"
require "./models/SipPacket"
require "./models/PacketFactory"
#require "./models/DataModels"
class SipReciever

  def initialize (address, port)
    @server = UDPSocket.new
    @server.bind address,port
    @buffer = uninitialized UInt8[2048]
  end

  def listen (&result)

    while (1==1)
      bytes,addr  = @server.receive @buffer.to_slice
      msg = String.new(@buffer.to_slice[0,bytes])
      yield addr,msg,bytes

    end
  end
end

sip = SipReciever.new "127.0.0.1", 5060
pf = PacketFactory.new
client = UDPSocket.new
sip.listen do |addr,msg,bytes|
  puts "\nMessage from: #{addr}\n"
  puts "==============================================\n"
  state = 0
  packet = SipPacket.new
  packet.is_verbose
  packet.interpret(addr,msg,bytes)
  print packet.dump_packet
  if packet.@mode == :register
    client.connect addr.address,addr.port

    reply = pf.create_OK packet
    rep = reply.dump_packet
    sip.@server.send(rep,addr)
    print rep
  end
end
