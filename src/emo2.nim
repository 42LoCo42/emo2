import std/[asyncnet, asyncdispatch, strutils, ropes, lists]
import playlist

var globalList: Playlist

proc handle(client: AsyncSocket) {.async.} =
  var position: Position = nil # the current playlist position = the most recently emitted song
  defer: client.close

  while true:
    let line = await client.recvLine
    if line == "": # client closed the connection
      break
    elif line == "\r\L": # empty line received
      continue

    let words = line.split " "
    let cmd   = words[0]
    let args  = if words.len > 1: words[1 .. words.high] else: @[]

    template want(num: int) =
      ## Require a minimum number of arguments.
      ## If the requirement is not met, send an error to the client.
      if args.len < num:
        await client.send "error args " & $num & "\n"
        continue

    var res: Rope
    proc sendLine(line: string) =
      ## Simulate sending a line by appending it to the cache (`res`).
      ## The given line must not end with a line terminator (it will be added by this function).
      res.add line & "\n"

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
        # we have an old element, decrease its refcount
        dec position.value.refcount

        # if old element is not referenced anymore and
        # is the start of the playlist, delete it
        if position.value.refcount <= 0 and position == globalList.head:
          globalList.delHead

        # possibly generate a new song
        if position.next == nil:
          globalList.addFromGenerator#

        # switch to next song
        position = position.next

      # at this point, we are at the next song, so we increase its refcount
      inc position.value.refcount

    proc nextCmd =
      advance()
      sendLine position.value.song

    case cmd
    of "queue":
      want(0)
      if position == nil:
        for i in globalList: sendLine $i
      else:
        for i in position.itemsFrom: sendLine $i
      sendLine "end"

    of "add":
      want(1)
      for newSong in args:
        globalList.addSong newSong
        sendLine "added " & newSong

    of "next":
      want(0)
      nextCmd()

    of "clear":
      want(0)
      # go to the last element
      while position.next != nil:
        advance()
      # and then to the next (which is new)
      nextCmd()

    else:
      sendLine "error unknown"

    await client.send $res

proc main {.async.} =
  let server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr 37812.Port
  server.listen

  while true:
    let client = await server.accept
    asyncCheck client.handle

asyncCheck main()
runForever()
