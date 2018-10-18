#ifndef LIBGURI_URI_PARSER_H_
#define LIBGURI_URI_PARSER_H_

#ifdef __cplusplus
extern "C"{
#endif

#include <stdlib.h>
#include <stddef.h>

/* TODO:
 * Normalization and Comparison
 * http://tools.ietf.org/html/rfc3986#section-6
 */

#include <glib.h>

struct uri_s {
  GStringChunk *chunk;
  char *scheme;
  char *userinfo;
  char *host;
  char *path;
  char *query;
  char *fragment;
  unsigned int port;
};

typedef struct uri_s uri_t;

extern uri_t *uri_new(void);
extern int uri_parse(uri_t *u, const char *buf, size_t len, const char **error_at);
extern void uri_clear(uri_t *u);
extern void uri_free(uri_t *u);

extern void uri_set_scheme(uri_t *u, const char *s, ssize_t l);
extern void uri_set_userinfo(uri_t *u, const char *s, ssize_t l);
extern void uri_set_host(uri_t *u, const char *s, ssize_t l);
extern void uri_set_path(uri_t *u, const char *s, ssize_t l);
extern void uri_set_query(uri_t *u, const char *s, ssize_t l);
extern void uri_set_fragment(uri_t *u, const char *s, ssize_t l);

extern void uri_normalize(uri_t *u);
extern char *uri_compose(uri_t *u);
extern char *uri_compose_partial(uri_t *u);
extern void uri_transform(uri_t *base, uri_t *relative, uri_t *transformed);

#ifdef __cplusplus
}
#endif

#endif  // LIBGURI_URI_PARSER_H_
