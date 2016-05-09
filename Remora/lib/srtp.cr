@[Link("srtp")]
lib LibSrtp
  struct RtpSenderCtxT
    message : RtpMsgT
    socket : LibC::Int
    srtp_ctx : SrtpCtxT
    addr : SockaddrIn
  end
  alias RtpSenderT = RtpSenderCtxT*
  struct RtpMsgT
    header : SrtpHdrT
    body : LibC::Char[16384]
  end
  struct SrtpHdrT
    cc : UInt8
    x : UInt8
    p : UInt8
    version : UInt8
    pt : UInt8
    m : UInt8
    seq : Uint16T
    ts : Uint32T
    ssrc : Uint32T
  end
  alias Uint16T = LibC::UShort
  alias Uint32T = LibC::UInt
  type SrtpCtxT = Void*
  struct SockaddrIn
    sin_family : LibC::Short
    sin_port : LibC::UShort
    sin_addr : InAddr
    sin_zero : LibC::Char[8]
  end
  struct InAddr
    s_addr : LibC::ULong
  end
  fun rtp_sendto(sender : RtpSenderT, msg : Void*, len : LibC::Int) : LibC::Int
  struct RtpReceiverCtxT
    message : RtpMsgT
    socket : LibC::Int
    srtp_ctx : SrtpCtxT
    addr : SockaddrIn
  end
  alias RtpReceiverT = RtpReceiverCtxT*
  fun rtp_recvfrom(receiver : RtpReceiverT, msg : Void*, len : LibC::Int*) : LibC::Int
  fun rtp_receiver_init(rcvr : RtpReceiverT, sock : LibC::Int, addr : SockaddrIn, ssrc : LibC::UInt) : LibC::Int
  fun rtp_sender_init(sender : RtpSenderT, sock : LibC::Int, addr : SockaddrIn, ssrc : LibC::UInt) : LibC::Int
  enum SrtpSecServT
    SecServNone = 0
    SecServConf = 1
    SecServAuth = 2
    SecServConfAndAuth = 3
  end
  fun srtp_sender_init(rtp_ctx : RtpSenderT, name : SockaddrIn, security_services : SrtpSecServT, input_key : UInt8*) : LibC::Int
  fun srtp_receiver_init(rtp_ctx : RtpReceiverT, name : SockaddrIn, security_services : SrtpSecServT, input_key : UInt8*) : LibC::Int
  struct SrtpPolicyT
    ssrc : SrtpSsrcT
    rtp : SrtpCryptoPolicyT
    rtcp : SrtpCryptoPolicyT
    key : UInt8*
    ekt : SrtpEktPolicyT
    window_size : LibC::ULong
    allow_repeat_tx : LibC::Int
    enc_xtn_hdr : LibC::Int*
    enc_xtn_hdr_count : LibC::Int
    next : SrtpPolicyT*
  end
  struct SrtpSsrcT
    type : SrtpSsrcTypeT
    value : LibC::UInt
  end
  enum SrtpSsrcTypeT
    SsrcUndefined = 0
    SsrcSpecific = 1
    SsrcAnyInbound = 2
    SsrcAnyOutbound = 3
  end
  struct SrtpCryptoPolicyT
    cipher_type : SrtpCipherTypeIdT
    cipher_key_len : LibC::Int
    auth_type : SrtpAuthTypeIdT
    auth_key_len : LibC::Int
    auth_tag_len : LibC::Int
    sec_serv : SrtpSecServT
  end
  alias SrtpCipherTypeIdT = Uint32T
  alias SrtpAuthTypeIdT = Uint32T
  type SrtpEktPolicyT = Void*
  fun rtp_sender_init_srtp(sender : RtpSenderT, policy : SrtpPolicyT*) : LibC::Int
  fun rtp_sender_deinit_srtp(sender : RtpSenderT) : LibC::Int
  fun rtp_receiver_init_srtp(sender : RtpReceiverT, policy : SrtpPolicyT*) : LibC::Int
  fun rtp_receiver_deinit_srtp(sender : RtpReceiverT) : LibC::Int
  fun rtp_sender_alloc : RtpSenderT
  fun rtp_sender_dealloc(rtp_ctx : RtpSenderT)
  fun rtp_receiver_alloc : RtpReceiverT
  fun rtp_receiver_dealloc(rtp_ctx : RtpReceiverT)
end

