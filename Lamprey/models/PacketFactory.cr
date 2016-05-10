require "./SipPacket"


class PacketFactory

  def create_OK (packet : SipPacket)
    reply = SipPacket.new
    reply.add_header "Via", "SIP/2.0/UDP localhost:5060;branch="+packet.@branch+";recieved=127.0.0.1;rport=5060"
    reply.add_header "From", "<"+packet.@from+">" #@todo to_tag
    reply.add_header "To","<"+packet.@to+">;tag="+packet.@from_tag #@todo to_tag
    reply.add_header "CSeq",(packet.@cseq.to_s)+" "+packet.@cseq_type.to_s
    reply.add_header "Contact",packet.@sip_name+" <"+packet.@contact_sip+":5062>"
    reply.add_header "Call-ID",packet.@call_id
    reply.add_header "Expires",7200
    reply.add_header "Content-length",0
    reply.add_header "Server","Lamprey v0.1"
    reply.heading "SIP/2.0 200 OK"

    print "CREATED PACKET\n"
    return reply
  end

end
