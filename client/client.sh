#!/usr/bin/env bash

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" || exit 1

send() {
	echo "$@" >&"${nc[1]}"
}

recv() {
	read -ru "${nc[0]}" "$@"
}

cmd() {
	printf '{"command":[%s]}\n' "$(
		printf '"%s"\n' "$@" | paste -sd,
	)" >&"${mpv[1]}"
}

(($# > 0)) && {
	echo "client ready" >&2
	url="$1"

	# open connections. this part massively triggers shellcheck
	mpv=(0 0)
	nc=(0 0)
	exec {mpv[0]}<"$2"
	exec {mpv[1]}>"$3"
	exec {nc[0]}<"$4"
	exec {nc[1]}>"$5"

	paused=1
	setpause() {
		(($# > 0)) && paused="$1"
		bools=("false" "true")
		printf '{"command":["set_property","pause",%s]}\n' \
			"${bools[$paused]}" >&"${mpv[1]}"
	}

	loadNextSong() {
		declare song
		send next
		recv song
		cmd loadfile "$url$song"
		setpause 0
		cmd run "$SHELL" -c "sleep 1 && echo unlock"
		emo wall "$song"
	}

	oldSong=
	oldPercent=0
	canComplete=1 # needed for completion debounce

	while read -ru "${mpv[0]}" cmd song time dur percent; do
		cmd="${cmd##*[K}" # remove leading escape sequences
		if [ "$cmd" == "[script]" ]; then
			cmd="$song" # second argument
		fi

		case "$cmd" in
		stat)
			# strip URL from song
			song="${song#"$url"}"
			echo -ne "[2K\r$song: $time/$dur ($percent)" >&2
			((paused)) && echo -n " (paused)" >&2

			oldSong="$song"
			oldPercent="$percent"
			;;
		next)
			((canComplete)) && {
				# lock completion trigger
				canComplete=0

				# print message & tell server to complete when >= 80%
				echo -ne "\nfinished $oldSong with $oldPercent" >&2
				(("${oldPercent%\%}" >= 80)) && {
					send "complete $oldSong"
					echo -n ", update count" >&2
				}
				echo >&2

				loadNextSong
			}
			;;
		unlock) canComplete=1 ;;
		pause) setpause "$((1 - paused))" ;;
		esac
	done
	exit
}

host="$(get-kyoku-ip)"
port=37812

url="http://$host:8000/songs/"

coproc nc (nc "$host" "$port")
coproc hotkey (sxhkd -c "hotkeys")

# shellcheck disable=SC2016
# we don't want to expand ${} here
coproc mpv (mpv \
	--script=script.lua \
	--idle=yes \
	--no-video \
	--no-input-terminal \
	--input-ipc-client=fd://0 \
	--term-status-msg='stat ${path} ${time-pos} ${duration} ${percent-pos}%\n' \
	2>&1
)

# shellcheck disable=SC2046
# splitting is intended, so forgive me god
coproc _ ("$0" "$url" $(printf "/proc/$$/fd/%d " "${mpv[@]}" "${nc[@]}"))

getQueue() {
	send queue
	queue=()
	while true; do
		recv code name; declare code name
		[ "$code" == "end" ] && break
		queue+=("$name")
	done
}

while read -ru "${hotkey[0]}" cmd; do
	echo -e "\nHOTKEY $cmd"
	case "$cmd" in
		next)
			cmd print-text next
			;;
		toggle)
			cmd print-text pause
			;;
		restart)
			cmd seek 0 absolute
			;;
		repeat)
			# if next song is not the current one, clear
			getQueue
			[ "${queue[1]}" != "$song" ] && send clear

			send add "$song"
			recv
			;;
	esac
done
