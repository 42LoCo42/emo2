import std/[lists, db_sqlite, random, math, strutils]

let db = open("songs.db", "", "", "")

type
  PlaylistItem* = tuple
    song: string
    refcount: int

  Playlist* = SinglyLinkedList[PlaylistItem]
  Position* = SinglyLinkedNode[PlaylistItem]

func `$`*(item: PlaylistItem): string =
  item.song

iterator itemsFrom*[T](node: SinglyLinkedNode[T]): T =
  var current = node
  while current != nil:
    yield current.value
    current = current.next

proc delHead*(list: var SinglyLinkedList) =
  if list.head != nil:
    list.head = list.head.next

proc addSong*(playlist: var Playlist, song: string) =
  playlist.add (song, 0) # start with no references, they will be changed by clients later

proc addFromGenerator*(playlist: var Playlist) =
  var songs: seq[string]
  var totals: seq[int]
  for row in db.fastRows(sql "select path, count + boost from songs"):
    songs.add row[0]
    totals.add row[1].parseInt

  let song = songs.sample totals.cumsummed
  stderr.writeLine "generator returns " & song
  playlist.addSong song
