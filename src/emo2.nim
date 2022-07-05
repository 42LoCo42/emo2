import std/[os, asyncnet, asyncdispatch, strutils, ropes, lists, db_sqlite]
import playlist
import zeolite

let identity = zeolite.createIdentity()
var globalList: Playlist

proc trustAll(pk: SignPK): bool =
  true

proc handle(socket: AsyncSocket) {.async.} =
  var position: Position = nil # the current playlist position = the most recently emitted song
  var channel = await zeolite.createChannel(identity, socket, trustAll)
  defer: channel.sock.close

  proc finish =
    ## Leave current song, possible deleting it if we were the last referent and
    ## and the song is the last element in the playlist
    # we have an old element, decrease its refcount
    dec position.value.refcount

    # if old element is not referenced anymore and
    # is the start of the playlist, delete it
    if position.value.refcount <= 0 and position == globalList.head:
      globalList.delHead

  proc advance =
    ## Advances `position` to the next song in the playlist.
    ## If there is no current song selected, go to the start of the playlist.
    ## If `generateNewSong` is false, no new song will be generated
    ## when `position` is at the end of the playlist.

    if position == nil:
      # go to start of playlist
      position = globalList.head
      if position == nil:
        # playlist is empty, add new element
        globalList.addFromGenerator
        position = globalList.head
    else:
      finish() # finish current song

      # possibly generate a new song
      if position.next == nil:
        globalList.addFromGenerator

      # switch to next song
      position = position.next

    # at this point, we are at the next song, so we increase its refcount
    inc position.value.refcount

  proc clearCmd =
    # potentially join queue
    if position == nil:
      advance()

    # go to the last element
    while position.next != nil:
      advance()

  try:
    while true:
      defer: echo globalList

      let line = strip(await channel.recv)
      if line == "":
        continue

      let parts = line.split(" ", maxsplit = 1)
      let cmd   = parts[0]
      let arg   = if parts.len > 1: parts[1] else: ""

      var res: Rope
      proc sendLine(line: string) =
        ## Simulate sending a line by appending it to the cache (`res`).
        ## The given line must not end with a line terminator (it will be added by this function).
        res.add line & "\n"

      proc nextCmd =
        advance()
        sendLine position.value.song

      case cmd
      of "queue":
        if position == nil:
          for i in globalList: sendLine "queued " & $i
        else:
          for i in position.itemsFrom: sendLine "queued " & $i
        sendLine "end"

      of "add":
        if arg.len == 0:
          sendLine "error args"
        else:
          globalList.addSong arg
          sendLine "added " & arg

      of "next":
        nextCmd()

      of "clear":
        clearCmd()

      of "complete":
        if arg.len == 0:
          sendLine "error args"
        else:
          complete arg

      of "getTable":
        if arg.len == 0:
          sendLine "error args"
        else:
          try:
            for row in db.fastRows(sql "select * from " & arg):
              sendLine row.join "\t"
            sendLine ""
          except DbError:
            sendLine "error " & getCurrentExceptionMsg()

      of "mergeChanges":
        while true:
          let change = strip(await channel.recv)
          if change == "":
            break

          let parts = change.split "\t"
          let song  = parts[0]
          let diff  = parts[1].parseInt
          db.exec(sql "update songs set count = count + ? where path = ?", diff, song)

      else:
        echo "unknown command ", line
        sendLine "error unknown"

      await channel.send $res
  except:
    # client closed the connection
    # decrease refcount of current song, process queue cleanup
    echo "Lost client: ", getCurrentExceptionMsg()
    clearCmd()
    finish()

proc main {.async.} =
  let args = commandLineParams()
  if args.len < 2:
    quit "Usage: $1 address port" % [getAppFilename()]

  zeolite.init()

  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(args[1].parseInt.Port, args[0])
  server.listen

  echo "emo2: ready for connections!"
  while true:
    let client = await server.accept
    echo "accepted client"
    asyncCheck client.handle

asyncCheck main()
runForever()
