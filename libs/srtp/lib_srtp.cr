@[Include("ekt.h")]
@[Include("rtp.h")]
@[Include("srtp.h")]
@[Link("srtp")]

lib LibSrtp
  # $lines : Void
  # $cols : Void
  fun rtp_sendto
  fun rtp_recvfrom
  fun rtp_receiver_init

  fun srtp_init
  fun srtp_shutdown
  fun srtp_protect
  fun srtp_unprotect
  fun srtp_create
  fun srtp_add_stream
  fun srtp_remove_stream
  fun srtp_update
  fun srtp_update_stream
  fun srtp_crypto_policy_set_rtp_default
  fun srtp_crypto_policy_set_rtcp_default
  fun srtp_crypto_policy_set_aes_cm_128_hmac_sha1_32
  fun srtp_crypto_policy_set_aes_cm_128_null_auth
  fun srtp_crypto_policy_set_null_cipher_hmac_sha1_80
  
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
  fun srtp_ekt_alloc
  fun srtp_ekt_stream_init
  fun srtp_ekt_stream_init_from_policy
  fun srtp_stream_init_from_ekt
  fun srtp_ekt_write_data
  fun srtp_ekt_tag_verification_preproces
  fun srtp_ekt_tag_verification_postproces
  fun srtp_stream_srtcp_auth_tag_generation_preprocess
  fun srtcp_auth_tag_generation_postprocess
##  fun wgetch
end
