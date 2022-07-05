import std/[asyncdispatch, asyncnet, strutils]

# CODEGEN START
type
  SignPK* = array[32U, uint8]
  SignSK  = array[(32U + 32U), uint8]
  EphPK   = array[32U, uint8]
  EphSK   = array[32U, uint8]
  SymK    = array[32U, uint8]
  Header  = array[24U, uint8]
# CODEGEN END

type
  cstringConstImpl {.importc: "const unsigned char*".} = cstring
  ccstring* = distinct cstringConstImpl

  crypto_secretstream_xchacha20poly1305_state {.importc, header: "sodium.h".} = object
  State = crypto_secretstream_xchacha20poly1305_state

{.passL: "-lsodium".}
{.push importc.}
let crypto_sign_BYTES     {.header: "sodium.h".}: cint
let crypto_box_NONCEBYTES {.header: "sodium.h".}: cint
let crypto_box_MACBYTES   {.header: "sodium.h".}: cint
let crypto_secretstream_xchacha20poly1305_ABYTES {.header: "sodium.h".}: cint

proc sodium_init: cint
proc randombytes_buf(buf: pointer, size: csize_t)

proc crypto_sign_keypair(pk: SignPK, sk: SignSK): cint
proc crypto_sign(
  signed:  ptr uint8, signedLen:  ptr culonglong,
  message: ccstring,  messageLen:     culonglong,
  sk: ccstring
): cint
proc crypto_sign_open(
  message: ptr uint8, messageLen: ptr culonglong,
  signed:  ccstring,  signedLen:      culonglong,
  pk: ccstring
): cint

proc crypto_box_keypair(pk: EphPK, sk: EphSK): cint
proc crypto_box_easy(
  cipher: ptr uint8,
  message: ccstring, messageLen: culonglong,
  nonce: ccstring,
  pk: ccstring, sk: ccstring
): cint
proc crypto_box_open_easy(
  message: ptr uint8,
  cipher: ccstring, cipherLen: culonglong,
  nonce: ccstring,
  pk: ccstring, sk: ccstring
): cint

proc crypto_secretstream_xchacha20poly1305_keygen(key: SymK)
proc crypto_secretstream_xchacha20poly1305_init_push(
  state: ptr State, header: Header, key: ccstring
): cint
proc crypto_secretstream_xchacha20poly1305_push(
  state: ptr State,
  cipher:  ptr uint8, cipherLen:ptr culonglong,
  message: ccstring,  messageLen:   culonglong,
  ad: ccstring, adLen: culonglong,
  tag: uint8
): cint
proc crypto_secretstream_xchacha20poly1305_init_pull(
  state: ptr State, header: ccstring, key: ccstring
): cint
proc crypto_secretstream_xchacha20poly1305_pull(
  state: ptr State,
  message: ptr uint8, messageLen: ptr culonglong,
  tag: ptr uint8,
  cipher: ccstring, cipherLen: culonglong,
  ad: ccstring, adLen: culonglong
): cint
{.pop.}

type
  Identity* = ref object
    pk: SignPK
    sk: SignSK

  Channel* = ref object
    sock*:     AsyncSocket
    partner:   SignPK
    sendState: State
    recvState: State

  InitError     = object of CatchableError
  KeygenError   = object of CatchableError
  ProtocolError = object of CatchableError
  NoTrustError  = object of CatchableError
  SignError     = object of CatchableError
  VerifyError   = object of CatchableError
  EncryptError  = object of CatchableError
  DecryptError  = object of CatchableError

# wrappers
proc sign(msg: openarray[uint8], sk: SignSK): seq[uint8] =
  let storageLen = crypto_sign_BYTES + msg.len
  result = newSeq[uint8](storageLen)

  if crypto_sign(
    addr result[0], nil,
    cast[ccstring](unsafeAddr msg[0]), cast[culonglong](msg.len),
    cast[ccstring](unsafeAddr sk[0])
  ) != 0:
    raise newException(SignError, "Could not sign data")

proc verify(signed: openarray[uint8], pk: SignPK): seq[uint8] =
  let storageLen = signed.len - crypto_sign_BYTES
  result = newSeq[uint8](storageLen)

  if crypto_sign_open(
    addr result[0], nil,
    cast[ccstring](unsafeAddr signed[0]), cast[culonglong](signed.len),
    cast[ccstring](unsafeAddr pk[0])
  ) != 0:
    raise newException(VerifyError, "Could not verify data")

proc seal(msg: openarray[uint8], pk: EphPK, sk: EphSK): seq[uint8] =
  let storageLen = crypto_box_NONCEBYTES + crypto_box_MACBYTES + msg.len
  result = newSeq[uint8](storageLen)
  randombytes_buf(addr result[0], cast[csize_t](crypto_box_NONCEBYTES))

  if crypto_box_easy(
    addr result[crypto_box_NONCEBYTES],
    cast[ccstring](unsafeAddr msg[0]), cast[culonglong](msg.len),
    cast[ccstring](addr result[0]),
    cast[ccstring](unsafeAddr pk[0]), cast[ccstring](unsafeAddr sk[0])
  ) != 0:
    raise newException(EncryptError, "Could not encrypt data")

proc open(cipher: openarray[uint8], pk: EphPK, sk: EphSK): seq[uint8] =
  let storageLen = cipher.len - crypto_box_NONCEBYTES - crypto_box_MACBYTES
  result = newSeq[uint8](storageLen)

  if crypto_box_open_easy(
    addr result[0],
    cast[ccstring](unsafeAddr cipher[crypto_box_NONCEBYTES]),
    cast[culonglong](cipher.len - crypto_box_NONCEBYTES),
    cast[ccstring](unsafeAddr cipher[0]),
    cast[ccstring](unsafeAddr pk[0]), cast[ccstring](unsafeAddr sk[0])
  ) != 0:
    raise newException(DecryptError, "Could not decrypt data")

proc streamInitEncrypt(state: ptr State, key: SymK): Header =
  if crypto_secretstream_xchacha20poly1305_init_push(
    state, result,
    cast[ccstring](unsafeAddr key[0])
  ) != 0:
    raise newException(EncryptError, "Could not initialize stream")

proc streamInitDecrypt(state: ptr State, key: SymK, header: Header) =
  if crypto_secretstream_xchacha20poly1305_init_pull(
    state,
    cast[ccstring](unsafeAddr header[0]),
    cast[ccstring](unsafeAddr key[0])
  ) != 0:
    raise newException(EncryptError, "Could not initialize stream")

# high level API
proc init* =
  if sodium_init() < 0:
    raise newException(InitError, "Could not initialize libsodium")

proc createIdentity*: Identity =
  result = Identity()
  if crypto_sign_keypair(result.pk, result.sk) != 0:
    raise newException(KeygenError, "Could not generate keypair")

proc createChannel*(
  identity: Identity,
  sock: AsyncSocket,
  trust: proc(pk: SignPK): bool
): Future[Channel] {.async.} =
  result = Channel()
  result.sock = sock

  # exchange & check protocol
  const protocol = "zeolite1"
  var otherProtocol: string
  await sock.send protocol
  otherProtocol = await sock.recv protocol.len
  if protocol != otherProtocol:
    raise newException(
      ProtocolError,
      "Protocols don't match: Expected $1, but got $2" % [protocol, otherProtocol]
    )

  # exchange public signing keys (client identification)
  await sock.send(addr identity.pk[0], identity.pk.len)
  discard await sock.recvInto(addr result.partner, result.partner.len)

  # check whether we should trust this client
  if not trust(result.partner):
    raise newException(NoTrustError, "We don't trust this client")

  # create, sign & exchange ephemeral keys (for shared key transfer)
  var ephPK: EphPK
  var ephSK: EphSK
  if crypto_box_keypair(ephPK, ephSK) != 0:
    raise newException(KeygenError, "Could not create ephemeral keys")
  var ephMsg = ephPK.sign identity.sk
  await sock.send(addr ephMsg[0], ephMsg.len)

  # read & verify ephemeral public key
  discard await sock.recvInto(addr ephMsg[0], ephMsg.len)
  let rawOtherEphPK = verify(ephMsg, result.partner)
  var otherEphPK: EphPK
  copyMem(addr otherEphPK[0], unsafeAddr rawOtherEphPK[0], otherEphPK.len)
  # why can't we convert seq to array, this is cringe

  # create, encrypt & send symmetric sender key
  var sendKey: SymK
  crypto_secretstream_xchacha20poly1305_keygen(sendKey)
  var symMsg = seal(sendKey, otherEphPK, ephSk)
  await sock.send(addr symMsg[0], symMsg.len)

  # receive & decrypt symmetric receiver key
  discard await sock.recvInto(addr symMsg[0], symMsg.len)
  let rawRecvKey = open(symMsg, otherEphPK, ephSk)
  var recvKey: SymK
  copyMem(addr recvKey[0], unsafeAddr rawRecvKey[0], recvKey.len)

  # init stream states
  var header: Header
  header = streamInitEncrypt(addr result.sendState, sendKey)
  await sock.send(addr header[0], header.len)
  discard await sock.recvInto(addr header[0], header.len)
  streamInitDecrypt(addr result.recvState, recvKey, header)

proc send*(channel: Channel, msg: string) {.async.} =
  let msgLen = cast[uint32](msg.len)
  await channel.sock.send(unsafeAddr msgLen, sizeof msgLen)

  let cipherLen = cast[int32](msg.len + crypto_secretstream_xchacha20poly1305_ABYTES)
  var cipher = newSeq[uint8](cipherLen)

  if crypto_secretstream_xchacha20poly1305_push(
    addr channel.sendState,
    addr cipher[0], nil,
    cast[ccstring](msg.cstring), cast[culonglong](msg.len),
    nil, 0, 0
  ) != 0:
    raise newException(EncryptError, "Could not encrypt data")

  await channel.sock.send(addr cipher[0], cipher.len)

proc recv*(channel: Channel): Future[string] {.async.} =
  var msgLen: uint32
  discard await channel.sock.recvInto(addr msgLen, sizeof msgLen)
  var msg = newSeq[uint8](msgLen)

  var cipher = newSeq[uint8](
    msgLen +
    cast[uint32](crypto_secretstream_xchacha20poly1305_ABYTES)
  )
  discard await channel.sock.recvInto(addr cipher[0], cipher.len)

  if crypto_secretstream_xchacha20poly1305_pull(
    addr channel.recvState,
    addr msg[0], nil,
    nil,
    cast[ccstring](addr cipher[0]), cast[culonglong](cipher.len),
    nil, 0
  ) != 0:
    raise newException(DecryptError, "Could not decrypt data")

  result = newString(msgLen)
  copyMem(addr result[0], addr msg[0], msg.len)
