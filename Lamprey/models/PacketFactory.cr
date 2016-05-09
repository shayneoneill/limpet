require "./SipPacket"


class PacketFactory

  def create_OK (packet : SipPacket)
    reply = SipPacket.new
    reply.add_header "SIP/2.0","200 OK"
    #@todo remove hardwiring
    reply.add_header "Via", "localhost:5060;branch="+packet.@branch+";recieved=127.0.0.1"
    reply.add_header "To",packet.@to #@todo to_tag
    reply.add_header "From",packet.@from+";tag="+packet.@from_tag #@todo to_tag
    reply.add_header "CSeq",packet.@csqeq+" "+packet.@cseq_type
    reply.add_header "Contact","<"+packet.@contact_sip+">"
    reply.add_header "Expires",7200
    reply.add_header "Content-length",0
    return reply
  end

end
