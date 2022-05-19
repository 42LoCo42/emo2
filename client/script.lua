-- this thing does the magic
function on_end_file(event)
	print("next")
end

mp.register_event("end-file", on_end_file)
