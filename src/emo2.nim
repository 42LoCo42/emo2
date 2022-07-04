import std/[strutils, db_sqlite, os]

let db = open("songs.db", "", "", "")

type send = proc(coro: pointer, channel: pointer, msg: cstring)

{.compile: "main.c".}
{.passL: "-lsodium -lkrimskrams -lzeolite".}

{.push importc.}
proc entrypoint(address: cstring, port: cstring)
{.pop.}

{.push exportc.}
proc complete(song: cstring) =
  echo "completing ", song
  let count = db.getValue(sql "select count from songs where path = ?", song)
  if count.len == 0:
    db.exec(sql "insert into songs values (?, 1, 1)", song)
  else:
    db.exec(sql "update songs set count = ? + 1 where path = ?", count, song)

proc getTable(send: send, coro: pointer, channel: pointer, table: cstring) =
  try:
    for row in db.fastRows(sql "select * from " & $table):
      send(coro, channel, cstring(row.join("\t") & "\n"))
    send(coro, channel, "\n")
  except DbError:
    send(coro, channel, cstring("error " & getCurrentExceptionMsg() & "\n"))

proc mergeChanges(data: pointer, recv: proc(data: pointer): cstring) =
  while true:
    let rawChange = recv(data)
    defer: rawChange.dealloc

    let change = ($rawChange).strip

    if change == "":
      break

    let parts = change.split "\t"
    if parts.len != 2:
      echo "mergeChanges needs 2 parts"
      break

    let song  = parts[0]
    let diff  = parts[1].parseInt
    db.exec(sql "update songs set count = count + ? where path = ?", diff, song)

# proc onDisconnect(pos: var Position) =
#   clear(pos)
#   finish(pos)
{.pop.}

let args = commandLineParams()
if args.len < 2:
  quit "Usage: $1 address port" % [getAppFilename()]
entrypoint(cstring(args[0]), cstring(args[1]))
