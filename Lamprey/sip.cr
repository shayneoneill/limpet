require "socket"
require "./lib/SipPacket"
require "./models/Models"
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

sip = SipReciever.new "0.0.0.0", 5060

sip.listen do |addr,msg,bytes|
  puts "\nMessage from: %s #{addr}\n"
  puts "==============================================\n"
  state = 0
  x = SipPacket.new
  x.interpret(addr,msg,bytes)
end
