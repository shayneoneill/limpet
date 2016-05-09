###@[Include("/usr/local/include/srtp2/ekt.h")]
@[Include("./rtp.h")]
@[Include("./srtp.h")]
@[Link("srtp")]
lib LibSrtp
  # $lines : Void
  # $cols : Void
  fun rtp_sendto
  fun rtp_recvfrom
  fun rtp_receiver_init
  fun rtp_sender_init
  fun srtp_sender_init
  fun srtp_receiver_init
  fun rtp_sender_init_srtp
  fun rtp_sender_deinit_srtp
  fun rtp_receiver_init_srtp
  fun rtp_receiver_deinit_srtp
  fun rtp_sender_alloc
  fun rtp_sender_dealloc
  fun rtp_receiver_alloc
  fun rtp_receiver_dealloc
##  fun wgetch
end
