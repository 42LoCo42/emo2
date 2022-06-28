type
  crypto_secretstream_xchacha20poly1305_state = array[52, uint8]
type
  sign_pk* = array[32U, uint8]
type
  sign_sk* = array[(32U + 32U), uint8]
type
  eph_pk* = array[32U, uint8]
type
  eph_sk* = array[32U, uint8]
type
  sym_k* = array[32U, uint8]
type
  error* {.size: sizeof(cint).} = enum
    SUCCESS = 0, EOF_ERROR, RECV_ERROR, SEND_ERROR, PROTOCOL_ERROR, KEYGEN_ERROR,
    TRUST_ERROR, SIGN_ERROR, VERIFY_ERROR, ENCRYPT_ERROR, DECRYPT_ERROR
type
  trust_callback* = proc (a1: sign_pk): error
type
  zeolite* {.bycopy.} = object
    sign_pk*: sign_pk
    sign_sk*: sign_sk
type
  channel* {.bycopy.} = object
    fd*: cint
    other_pk*: sign_pk
    send_state*: crypto_secretstream_xchacha20poly1305_state
    recv_state*: crypto_secretstream_xchacha20poly1305_state
proc init*(): cint {.importc: "zeolite_init", dynlib: "libzeolite.so".}
proc free*() {.importc: "zeolite_free", dynlib: "libzeolite.so".}
proc create*(z: ptr zeolite): error {.importc: "zeolite_create",
                                 dynlib: "libzeolite.so".}
proc create_channel*(coro: ptr int; z: ptr zeolite; c: ptr channel; socket: cint;
                    cb: trust_callback) {.importc: "zeolite_create_channel",
                                        dynlib: "libzeolite.so".}
proc create_channel_now*(z: ptr zeolite; c: ptr channel; socket: cint; cb: trust_callback): cint {.
    importc: "zeolite_create_channel_now", dynlib: "libzeolite.so".}
proc channel_send*(coro: ptr int; c: ptr channel; msg: cstring; len: uint32): error {.
    importc: "zeolite_channel_send", dynlib: "libzeolite.so".}
proc channel_rekey*(coro: ptr int; c: ptr channel): error {.
    importc: "zeolite_channel_rekey", dynlib: "libzeolite.so".}
proc channel_close*(coro: ptr int; c: ptr channel): error {.
    importc: "zeolite_channel_close", dynlib: "libzeolite.so".}
proc channel_recv*(coro: ptr int; c: ptr channel; msg: ptr cstring;
                  len: ptr uint32): error {.importc: "zeolite_channel_recv",
    dynlib: "libzeolite.so".}
proc enc_b64*(msg: cstring; len: csize_t): cstring {.importc: "zeolite_enc_b64",
    dynlib: "libzeolite.so".}
proc dec_b64*(b64: cstring; len: csize_t; msg: ptr cstring): csize_t {.
    importc: "zeolite_dec_b64", dynlib: "libzeolite.so".}
proc error_str*(e: error): cstring {.importc: "zeolite_error_str",
                                 dynlib: "libzeolite.so".}
proc print_b64*(msg: cstring; len: csize_t) {.importc: "zeolite_print_b64",
    dynlib: "libzeolite.so".}
type
  handler_f* = proc (coro: ptr int; loop: ptr int;
                  channel: ptr channel): cint
proc multiServer*(z: ptr zeolite; `addr`: cstring; port: cstring;
                 trustCallback: trust_callback; handler: handler_f): cint {.
    importc: "zeolite_multiServer", dynlib: "libzeolite.so".}