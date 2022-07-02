import std/[os, strutils, lists, db_sqlite]
import playlist

var globalList: Playlist

{.compile: "main.c".}
{.passL: "-lsodium -lkrimskrams -lzeolite".}

{.push importc.}
proc entrypoint(address: cstring, port: cstring)
{.pop.}

proc finish(pos: Position) =
  ## Leave current song, possible deleting it if we were the last referent and
  ## and the song is the last element in the playlist
  # we have an old element, decrease its refcount
  dec pos.value.refcount

  # if old element is not referenced anymore and
  # is the start of the playlist, delete it
  if pos.value.refcount <= 0 and pos == globalList.head:
    globalList.delHead

proc advance(pos: var Position) =
  ## Advances `position` to the next song in the playlist.
  ## If there is no current song selected, go to the start of the playlist.
  ## If `generateNewSong` is false, no new song will be generated
  ## when `position` is at the end of the playlist.

  if pos == nil:
    # go to start of playlist
    pos = globalList.head
    if pos == nil:
      # playlist is empty, add new element
      globalList.addFromGenerator
      pos = globalList.head
  else:
    finish(pos) # finish current song

    # possibly generate a new song
    if pos.next == nil:
      globalList.addFromGenerator

    # switch to next song
    pos = pos.next

  # at this point, we are at the next song, so we increase its refcount
  inc pos.value.refcount

type send = proc(data: pointer, song: cstring)

{.push exportc.}
proc printList =
  echo "Playlist:"
  for item in globalList:
    echo "\t" & $item

proc addToPlaylist(song: cstring) =
  globalList.addSong $song

proc queue(data: pointer, pos: Position, send: send) =
  if pos == nil:
    for item in globalList:
      send(data, cstring("queued " & item.song & "\n"))
  else:
    for item in pos.itemsFrom:
      send(data, cstring("queued " & item.song & "\n"))
  send(data, "end\n")

proc clear(pos: var Position) =
  # potentially join queue
  if pos == nil:
    advance(pos)

  # go to the last element
  while pos.next != nil:
    advance(pos)

proc next(data: pointer, pos: var Position, send: send) =
  advance(pos)
  send(data, cstring(pos.value.song & "\n"))

proc complete(song: cstring) =
  echo "completing ", song
  let count = db.getValue(sql "select count from songs where path = ?", song)
  if count.len == 0:
    db.exec(sql "insert into songs values (?, 1, 1)", song)
  else:
    db.exec(sql "update songs set count = ? + 1 where path = ?", count, song)

proc getTable(data: pointer, table: cstring, send: send) =
  try:
    for row in db.fastRows(sql "select * from " & $table):
      send(data, cstring(row.join("\t") & "\n"))
    send(data, "\n")
  except DbError:
    send(data, cstring("error " & getCurrentExceptionMsg() & "\n"))

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
{.pop.}

proc main =
  let args = commandLineParams()
  if args.len < 2:
    quit "Usage: $1 address port" % [getAppFilename()]
  entrypoint(cstring(args[0]), cstring(args[1]))

main()
