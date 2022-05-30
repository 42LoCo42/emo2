#!/usr/bin/env bash
{
	cat << EOF
create table songs (
	path text primary key,
	count integer not null,
	boost integer not null
);
EOF
	
	cd "$1" || exit 1
	find . -not -type d | sed 's|^..||' | while read -r path; do
		printf 'insert into songs values ("%s", 0, 1);\n' "$path"
	done
} | sqlite3 songs.db
