import std/[lists, db_sqlite, random, math, strutils]

randomize()

# proc addFromGenerator*(playlist: var Playlist) =
#   var songs: seq[string]
#   var totals: seq[int]
#   for row in db.fastRows(sql "select path, count + boost from songs"):
#     songs.add row[0]
#     totals.add row[1].parseInt
# 
#   let song = songs.sample totals.cumsummed
#   stderr.writeLine "generator returns " & song
#   playlist.addSong song
