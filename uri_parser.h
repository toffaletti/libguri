#include <stddef.h>

#ifdef URI_USE_GLIB
#include <glib.h>
#endif

typedef struct uri {
#ifdef URI_USE_GLIB
  GStringChunk *chunk;
#endif
  char *scheme;
  char *userinfo;
  char *host;
  char *path;
  char *query;
  char *fragment;
  unsigned int port;
} uri;

extern void uri_init(uri *u);
extern int uri_parse(uri *u, const char *buf, size_t len, const char **error_at);
extern void uri_clear(uri *u);
extern void uri_free(uri *u);
