require "./lib/srtp.cr"


##srtp_err_status_t error =



#rtp_sender_init(sender : RtpSenderT, sock : LibC::Int, addr : SockaddrIn, ssrc : LibC::UInt)
session = srtp
solicy = srtp_policy
policyP = pointer(policy)
sessionP = pointer(session)

key = Slice.new(30)
srtp_init();
#// set policy to describe a policy for an SRTP stream
crypto_policy_set_rtp_default(policyP.rtp)
crypto_policy_set_rtcp_default(policyP.rtcp)
policy.ssrc = ssrc
policy.key  = key
policy.next = NULL
#// set key to random value
crypto_get_random(key, 30);
#// allocate and initialize the SRTP x
srtp_create(sessionP, policy);
#// main loop: get rtp packets, send srtp packets
#while (1) {
while (1==1)
  #char rtp_buffer[2048];
  unsigned len;
  len = get_rtp_packet(rtp_buffer);
  srtp_protect(session, rtp_buffer, &len);
  send_srt
end
