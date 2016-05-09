CELT_SOURCES = celt/bands.c \
celt/celt.c \
celt/celt_encoder.c \
celt/celt_decoder.c \
celt/cwrs.c \
celt/entcode.c \
celt/entdec.c \
celt/entenc.c \
celt/kiss_fft.c \
celt/laplace.c \
celt/mathops.c \
celt/mdct.c \
celt/modes.c \
celt/pitch.c \
celt/celt_lpc.c \
celt/quant_bands.c \
celt/rate.c \
celt/vq.c

CELT_SOURCE_SSE = celt/x86/x86_cpu.c \
celt/x86/x86_celt_map.c \
celt/x86/pitch_sse.c

CELT_SOURCE_SSE4_1 = celt/x86/celt_lpc_sse.c

CELT_SOURCES_ARM = \
celt/arm/armcpu.c \
celt/arm/arm_celt_map.c

CELT_SOURCES_ARM_ASM = \
celt/arm/celt_pitch_xcorr_arm.s

CELT_AM_SOURCES_ARM_ASM = \
celt/arm/armopts.s.in