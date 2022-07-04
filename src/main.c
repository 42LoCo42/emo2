#include <err.h>
#include <krimskrams/coro.h>
#include <zeolite.h>

#define safef(fn, cond, ...) if(cond) fn(__VA_ARGS__);
#define safe(cond, ...) safef(warn, cond, __VA_ARGS__);
#define safex(cond, ...) safef(warnx, cond, __VA_ARGS__);

#define ERR_NEEDS_ARG "error: This function needs an argument!\n"
#define LEN_NEEDS_ARG strlen(ERR_NEEDS_ARG)

#define needsArg(msg)                       \
	if(arg == NULL) {                       \
		zeolite_channel_send(coro, c,       \
			(unsigned char*) ERR_NEEDS_ARG, \
			LEN_NEEDS_ARG                   \
		);                                  \
		free(buf);                          \
		continue;                           \
	}

zeolite_error trustAll(zeolite_sign_pk pk) {
	char* b64 = zeolite_enc_b64(pk, sizeof(zeolite_sign_pk));
	fprintf(stderr, "other client is %s\n", b64);
	free(b64);
	return SUCCESS;
}

typedef void (*send_f)(krk_coro_t* coro, zeolite_channel* c, char* msg);
void send(krk_coro_t* coro, zeolite_channel* c, char* msg) {
	zeolite_channel_send(coro, c, (unsigned char*) msg, strlen(msg));
}

char* recv(krk_coro_t* coro, zeolite_channel* c) {
	char*    buf = NULL;
	uint32_t len = 0;
	zeolite_channel_recv(coro, c, (unsigned char**) &buf, &len);
	return buf;
}

typedef struct song {
	char* name;
	int   refcount;
	struct song* next;
} song;

static struct {
	song* head;
	song* tail;
} globalList = {0};

void printList() {
	puts("Playlist:");
	for(song* s = globalList.head; s != NULL; s = s->next) {
		printf("	%s (%d)\n", s->name, s->refcount);
	}
}

void sendSong(krk_coro_t* coro, zeolite_channel* c, song* s) {
	char* buf = malloc(strlen(s->name) + 16);
	sprintf(buf, "%s (%d)\n", s->name, s->refcount);
	send(coro, c, buf);
	free(buf);
}

void addToPlaylist(char* name) {
	song* new = malloc(sizeof(song));
	new->name = name;
	new->refcount = 0;

	if(globalList.tail == NULL) {
		globalList.head = new;
		globalList.tail = new;
	} else {
		globalList.tail->next = new;
		globalList.tail = new;
	}
}

void delFirst() {
	if(globalList.head == NULL) {
		err(1, "delFirst called on empty list!");
	} else {
		song* ptr = globalList.head;
		globalList.head = ptr->next;
		free(ptr);
	}
}

void addFromGenerator() {
	addToPlaylist("generated");
}

void finish(song* pos) {
	// Leave current song, possible deleting it if we were the last referent and
	// and the song is the last element in the playlist
	// we have an old element, decrease its refcount

	pos->refcount--;
	if(pos->refcount <= 0 && pos == globalList.head) {
		delFirst();
	}
}

void advance(song** pos) {
	// Advances `position` to the next song in the playlist.
	// If there is no current song selected, go to the start of the playlist.
	// If `generateNewSong` is false, no new song will be generated
	// when `position` is at the end of the playlist.

	if(*pos == NULL) {
		*pos = globalList.head;
		if(*pos == NULL) {
			addFromGenerator();
			*pos = globalList.head;
		}
	} else {
		finish(*pos);

		if((*pos)->next == NULL) {
			addFromGenerator();
		}

		*pos = (*pos)->next;
	}

	(*pos)->refcount++;
}

void clear(song** pos) {
	if(*pos == NULL) {
		advance(pos);
	}

	while((*pos)->next != NULL) {
		advance(pos);
	}
}

void complete(char* song);

// void getTable(data* d, char* table, send_f);
// void mergeChanges(data* d, recv_f);
// void onDisconnect(song** pos);

int handler(
	krk_coro_t* coro, krk_eventloop_t* loop,
	zeolite_channel* c, song** pos
) {
	for(;;) {
		char*    buf = NULL;
		uint32_t len = 0;
		zeolite_error e = zeolite_channel_recv(coro, c, (unsigned char**) &buf, &len);
		if(e != SUCCESS) {
			warnx("Could not receive: %s", zeolite_error_str(e));
			krk_coro_error(coro);
		}

		if(len == 0) {free(buf); continue;}
		buf[len - 1] = 0; // remove trailing newline

		char* sep = strchr(buf, ' ');
		if(sep != NULL) *sep = 0; // separate cmd from arg
		char* arg = sep == NULL ? NULL : sep + 1;

		if(strcmp(buf, "add") == 0) {
			needsArg();
			addToPlaylist(arg);
		} else if(strcmp(buf, "queue") == 0) {
			for(song* s = *pos ? *pos : globalList.head; s != NULL; s = s->next) {
				sendSong(coro, c, s);
			}
			send(coro, c, "\n");
		} else if(strcmp(buf, "clear") == 0) {
			clear(pos);
		} else if(strcmp(buf, "next") == 0) {
			advance(pos);
			sendSong(coro, c, *pos);
		} else if(strcmp(buf, "complete") == 0) {
			needsArg();
			complete(arg);
		} else if(strcmp(buf, "getTable") == 0) {
			needsArg();
			// getTable(&me, arg, send);
		} else if(strcmp(buf, "mergeChanges") == 0) {
			// mergeChanges(&me, recv);
		} else {
			const char* err = "Error: unknown command\n";
			zeolite_channel_send(coro, c, (unsigned char*) err, strlen(err));
		}
	}

	krk_coro_finish(coro, NULL);
}

int outer(krk_coro_t* coro, krk_eventloop_t* loop, zeolite_channel* c) {
	song* pos = NULL;
	krk_coro_t inner = {0};
	krk_coro_mk(&inner, handler, 3, loop, c, &pos);
	for(;;) {
		krk_coro_run(&inner);

		switch(inner.state) {
			case PAUSED:
				printList();
				krk_coro_yield(coro, NULL);
				break;
			case ERRORED:
				// onDisconnect(&pos);
				printList();
				krk_coro_free(&inner);
				krk_coro_error(coro);
				break;
			default:
				err(1, "Impossible state");
		}
	}
}

void entrypoint(char* address, char* port) {
	krk_coro_stack = 1 << 20;

	safex(zeolite_init() < 0, "Could not init zeolite");

	zeolite z = {0};
	safex(zeolite_create(&z) < 0, "Could not create zeolite identity");

	zeolite_multiServer(
		&z,
		address,
		port,
		trustAll,
		outer
	);
}
