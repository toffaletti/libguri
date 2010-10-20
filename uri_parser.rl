#include "uri_parser.h"
#include <stdlib.h>
#include <assert.h>

%%{
  machine uri_parser;

  action mark {
    mark = fpc;
  }

  action scheme {
#ifdef URI_USE_GLIB
    u->scheme = g_string_chunk_insert_len(u->chunk, mark, fpc-mark);
#else
    u->scheme = strndup(mark, fpc-mark);
#endif
  }

  action userinfo {
#ifdef URI_USE_GLIB
    u->userinfo = g_string_chunk_insert_len(u->chunk, mark, fpc-mark);
#else
    u->userinfo = strndup(mark, fpc-mark);
#endif
  }

  action host {
#ifdef URI_USE_GLIB
    u->host = g_string_chunk_insert_len(u->chunk, mark, fpc-mark);
#else
    /* host may be called multiple times because
     * the parser isn't able to figure out the difference
     * between the userinfo and host until after the @ is encountered
     */
    if (u->host) { free(u->host); }
    u->host = strndup(mark, fpc-mark);
#endif
  }

  action port {
    u->port = strtol(mark, NULL, 0);
  }

  action path {
#ifdef URI_USE_GLIB
    u->path = g_string_chunk_insert_len(u->chunk, mark, fpc-mark);
#else
    u->path = strndup(mark, fpc-mark);
#endif
  }

  action query {
#ifdef URI_USE_GLIB
    u->query = g_string_chunk_insert_len(u->chunk, mark, fpc-mark);
#else
    u->query = strndup(mark, fpc-mark);
#endif
  }

  action fragment {
#ifdef URI_USE_GLIB
    u->fragment = g_string_chunk_insert_len(u->chunk, mark, fpc-mark);
#else
    u->fragment = strndup(mark, fpc-mark);
#endif
  }

  include uri_grammar "uri_grammar.rl";

  main := URI;
}%%

%% write data;

static void uri_zero(uri *u) {
/* zero everything *except* chunk */
  u->scheme = NULL;
  u->userinfo = NULL;
  u->host = NULL;
  u->path = NULL;
  u->query = NULL;
  u->fragment = NULL;
  u->port = 0;
}

void uri_init(uri *u) {
  uri_zero(u);
#ifdef URI_USE_GLIB
  u->chunk = g_string_chunk_new(1024);
#endif
}

int uri_parse(uri *u, const char *buf, size_t len, const char **error_at) {
  const char *mark = NULL;
  const char *p, *pe, *eof;
  int cs = 0;

  if (error_at != NULL) {
    *error_at = NULL;
  }

  %% write init;

  p = buf;
  pe = buf+len;
  eof = pe;

  %% write exec;

  if (cs == uri_parser_error && error_at != NULL) {
    *error_at = p;
  }

  return (cs != uri_parser_error && cs >= uri_parser_first_final);
}

void uri_clear(uri *u) {
#ifdef URI_USE_GLIB
  g_string_chunk_clear(u->chunk);
#else
  uri_free(u);
#endif
  uri_zero(u);
}

void uri_free(uri *u) {
#ifdef URI_USE_GLIB
  g_string_chunk_free(u->chunk);
#else
  if (u->scheme) free(u->scheme);
  if (u->userinfo) free(u->userinfo);
  if (u->host) free(u->host);
  if (u->path) free(u->path);
  if (u->query) free(u->query);
  if (u->fragment) free(u->fragment);
#endif
  uri_zero(u);
}

