type
  crypto_secretstream_xchacha20poly1305_state = array[52, uint8]
  sign_pk* = array[32U, uint8]
  sign_sk* = array[(32U + 32U), uint8]
  eph_pk* = array[32U, uint8]
  eph_sk* = array[32U, uint8]
  sym_k* = array[32U, uint8]
  error* {.size: sizeof(cint).} = enum
    SUCCESS = 0, EOF_ERROR, RECV_ERROR, SEND_ERROR, PROTOCOL_ERROR, KEYGEN_ERROR,
    TRUST_ERROR, SIGN_ERROR, VERIFY_ERROR, ENCRYPT_ERROR, DECRYPT_ERROR
  trust_callback* = proc (a1: sign_pk): error
  zeolite* {.bycopy.} = object
    sign_pk*: sign_pk
    sign_sk*: sign_sk
  channel* {.bycopy.} = object
    fd*: cint
    other_pk*: sign_pk
    send_state*: crypto_secretstream_xchacha20poly1305_state
    recv_state*: crypto_secretstream_xchacha20poly1305_state
proc init*(): cint {.importc: "zeolite_init", dynlib: "libzeolite.so".}
proc free*() {.importc: "zeolite_free", dynlib: "libzeolite.so".}
proc create*(z: ptr zeolite): error {.importc: "zeolite_create",
                                 dynlib: "libzeolite.so".}
proc create_channel*(z: ptr zeolite; c: ptr channel; socket: cint; cb: trust_callback): error {.
    importc: "zeolite_create_channel", dynlib: "libzeolite.so".}
proc channel_send*(c: ptr channel; msg: cstring; len: csize_t): error {.
    importc: "zeolite_channel_send", dynlib: "libzeolite.so".}
proc channel_rekey*(c: ptr channel): error {.importc: "zeolite_channel_rekey",
                                        dynlib: "libzeolite.so".}
proc channel_close*(c: ptr channel): error {.importc: "zeolite_channel_close",
                                        dynlib: "libzeolite.so".}
proc channel_recv*(c: ptr channel; msg: ptr cstring; len: ptr csize_t): error {.
    importc: "zeolite_channel_recv", dynlib: "libzeolite.so".}
proc enc_b64*(msg: cstring; len: csize_t): cstring {.importc: "zeolite_enc_b64",
    dynlib: "libzeolite.so".}
proc dec_b64*(b64: cstring; len: csize_t; msg: ptr cstring): csize_t {.
    importc: "zeolite_dec_b64", dynlib: "libzeolite.so".}
proc error_str*(e: error): cstring {.importc: "zeolite_error_str",
                                 dynlib: "libzeolite.so".}
proc print_b64*(msg: cstring; len: csize_t) {.importc: "zeolite_print_b64",
    dynlib: "libzeolite.so".}
