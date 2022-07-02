#include <err.h>
#include <krimskrams/coro.h>
#include <zeolite.h>

#define safef(fn, cond, ...) if(cond) fn(__VA_ARGS__);
#define safe(cond, ...) safef(warn, cond, __VA_ARGS__);
#define safex(cond, ...) safef(warnx, cond, __VA_ARGS__);

#define ERR_NEEDS_ARG "error: This function needs an argument!\n"
#define LEN_NEEDS_ARG strlen(ERR_NEEDS_ARG)

#define needsArg(msg)                               \
	if(arg == NULL) {                               \
		zeolite_channel_send(                       \
			coro, c, ERR_NEEDS_ARG, LEN_NEEDS_ARG); \
		free(buf);                                  \
		continue;                                   \
	}

typedef struct {
	krk_coro_t* coro;
	krk_eventloop_t* loop;
	zeolite_channel* c;
} data;

typedef void  (*send_f)(data* d, char* song);
typedef char* (*recv_f)(data* d);

void printList();
void addToPlaylist(char* song);
void queue(data* d, void* pos, send_f);
void clear(void** pos);
void next(data* d, void** pos, send_f);
void complete(char* song);
void getTable(data* d, char* table, send_f);
void mergeChanges(data* d, recv_f);

zeolite_error trustAll(zeolite_sign_pk pk) {
	char* b64 = zeolite_enc_b64(pk, sizeof(zeolite_sign_pk));
	fprintf(stderr, "other client is %s\n", b64);
	free(b64);
	return SUCCESS;
}

void send(data* d, char* song) {
	zeolite_channel_send(d->coro, d->c, song, strlen(song));
}

char* recv(data* d) {
	char*    buf = NULL;
	uint32_t len = 0;
	zeolite_channel_recv(d->coro, d->c, (unsigned char**) &buf, &len);
	return buf;
}

int handler(krk_coro_t* coro, krk_eventloop_t* loop, zeolite_channel* c) {
	data  me  = {coro, loop, c};
	void* pos = NULL;

	for(;;) {
		unsigned char* buf = NULL;
		uint32_t       len = 0;
		zeolite_error e = zeolite_channel_recv(coro, c, &buf, &len);
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
			queue(&me, pos, send);
		} else if(strcmp(buf, "clear") == 0) {
			clear(&pos);
		} else if(strcmp(buf, "next") == 0) {
			next(&me, &pos, send);
		} else if(strcmp(buf, "complete") == 0) {
			needsArg();
			complete(arg);
		} else if(strcmp(buf, "getTable") == 0) {
			needsArg();
			getTable(&me, arg, send);
		} else if(strcmp(buf, "mergeChanges") == 0) {
			mergeChanges(&me, recv);
		} else {
			const char* err = "Error: unknown command\n";
			zeolite_channel_send(coro, c, err, strlen(err));
		}

		printList();
	}

	krk_coro_finish(coro, NULL);
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
		handler
	);
}
