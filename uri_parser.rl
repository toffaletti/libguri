#include "uri_parser.h"
#include <stdlib.h>
#include <assert.h>
#include <ctype.h>
#include <string.h>

#include <stdio.h>

#ifdef URI_USE_GLIB
#define URI_DEFINE_SETTER(field) \
  void uri_set_##field(uri *u, const char *s, ssize_t l) { \
    if (s == 0) { u->field = 0; return; } \
    if (l == -1) { l = strlen(s); } \
    u->field = g_string_chunk_insert_len(u->chunk, s, l); \
  }
#else
#define URI_DEFINE_SETTER(field) \
  void uri_set_##field(uri *u, const char *s, ssize_t l) { \
    if (u->field) { free(u->field); }
    if (s == 0) { u->field = 0; return; } \
    if (l == -1) { l = strlen(s); } \
    u->field = strndup(s, l); \
  }
#endif

URI_DEFINE_SETTER(scheme)
URI_DEFINE_SETTER(userinfo)
URI_DEFINE_SETTER(host)
URI_DEFINE_SETTER(path)
URI_DEFINE_SETTER(query)
URI_DEFINE_SETTER(fragment)

%%{
  machine uri_parser;

  action mark {
    mark = fpc;
  }

  action scheme {
    uri_set_scheme(u, mark, fpc-mark);
  }

  action userinfo {
    uri_set_userinfo(u, mark, fpc-mark);
  }

  action host {
    /* host may be called multiple times because
     * the parser isn't able to figure out the difference
     * between the userinfo and host until after the @ is encountered
     */
    uri_set_host(u, mark, fpc-mark);
  }

  action port {
    u->port = strtol(mark, NULL, 0);
  }

  action path {
    uri_set_path(u, mark, fpc-mark);
  }

  action query {
    uri_set_query(u, mark, fpc-mark);
  }

  action fragment {
    uri_set_fragment(u, mark, fpc-mark);
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

%%{
# simple machine to normalize percent encoding in uris
  machine normalize_pct_encoded;

  action pct_encoded {
    char *d1 = (char *)(fpc-1);
    char *d2 = (char *)fpc;

    /* convert hex digits to upper case */
    *d1 = toupper(*d1);
    *d2 = toupper(*d2);

    /* convert hex to character */
    char c = 0;
    for (int i=0; i<2; i++) {
      if (d1[i] < 57) {
        c += (d1[i]-48)*(1<<(4*(1-i)));
      } else {
        c += (d1[i]-55)*(1<<(4*(1-i)));
      }
    }

    /* unescape characters that shouldn't be escaped */
    if (
      ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) /* alpha */
      || (c >= 0x30 && c <= 0x39) /* digit */
      || (c == 0x2D) /* hyphen */
      || (c == 0x2E) /* period */
      || (c == 0x5F) /* underscore */
      || (c == 0x7E) /* tilde */
      )
    {
      /* replace encoded value with character */
      *(d1-1) = c;
      memmove(d1, d2+1, pe-(d2+1));
      /* adjust internal state to match the buffer after memmove */
      pe = pe-2;
      /* add null terminator */
      *((char *)pe) = 0;
      fexec fpc-2;
    }
  }

  pct_encoded = ("%" xdigit xdigit) @pct_encoded;

  main := (^"%"+ | pct_encoded)*;
}%%

%% write data;

static void normalize_pct_encoded(const char *buf) {
  const char *p, *pe;
  int cs = 0;

  %% write init;

  p = buf;
  pe = buf+strlen(buf);

  %% write exec;

  assert (cs != normalize_pct_encoded_error);
}


static void remove_dot_segments(uri *u) {
  if (u->path == 0) return;
  size_t plen = strlen(u->path);
  switch (plen) {
    case 0:
      uri_set_path(u, "/", 1);
      return;
    case 1:
      return;
  }
  size_t segs_size = plen * sizeof(char *);
  unsigned int segm = 0;
  char *p = 0;
  if (segs_size) {
    char **segs = malloc(segs_size);
    char *segb = u->path;
    /* split path on / into a list of segments */
    for (p = u->path; *p != 0; p++) {
      if (*p == '/' && p != u->path) {
        /* ignore empty segment. for example: // */
        if (segb+1 != p) {
          *p = 0;
          /* put the pointer to the segment in segments array */
          segs[segm] = segb+1;
          segm++;
        }
        /* move begin pointer forward. reset end pointer to 0 */
        segb = p;
      }
    }
    /* final segment */
    if (segb+1 < u->path + plen) {
        segs[segm] = segb+1;
        segm++;
    } else if (segb+1 == u->path + plen) {
        segs[segm] = segb;
        segm++;
    }


    for (unsigned int segi = 0; segi < segm; segi++) {
      if (g_strcmp0(".", segs[segi]) == 0) {
        segs[segi] = 0;
      } else if (g_strcmp0("..", segs[segi]) == 0) {
        segs[segi] = 0;
        unsigned int segx = segi;
        while (segx >= 1 && segs[segx] == 0) {
          segx--;
        }
        segs[segx] = 0;
      }
    }

    /* reassemble path from segment pointers */
    p = u->path;
    for (unsigned int segi = 0; segi < segm; segi++) {
      char *pn = segs[segi];
      if (pn == 0) continue;
      *p = '/'; p++;
      if (*pn == '/') continue;
      while (*pn) {
        *p = *pn;
        p++;
        pn++;
      }
    }
    if (segm && segs[segm-1] == 0) {
      *p = '/'; p++;
    }
    free(segs);
  }

  if (segm == 0) {
    *p = '/'; p++;
  }

  *p = 0;
}

void uri_normalize(uri *u) {
  for (char *p = u->scheme; *p != 0; p++) {
    *p = tolower(*p);
  }
  if (u->userinfo) {
    normalize_pct_encoded(u->userinfo);
  }
  for (char *p = u->host; *p != 0; p++) {
    *p = tolower(*p);
  }
  normalize_pct_encoded(u->host);
  normalize_pct_encoded(u->path);
  remove_dot_segments(u);

  if (u->query) {
    normalize_pct_encoded(u->query);
  }
  if (u->fragment) {
    normalize_pct_encoded(u->fragment);
  }
}

char *uri_compose(uri *u) {
  GString *s = g_string_sized_new(1024);
  if (u->scheme) {
    g_string_append_printf(s, "%s:", u->scheme);
  }
  /* authority */
  if (u->userinfo || u->host) {
    g_string_append(s, "//");
  }
  if (u->userinfo) {
    g_string_append_printf(s, "%s@", u->userinfo);
  }
  if (u->host) {
    g_string_append(s, u->host);
    if (u->port) {
      g_string_append_printf(s, ":%u", u->port);
    }
  }
  if (u->path) {
    if (!g_str_has_prefix(u->path, "/")) {
      g_string_append(s, "/");
    }
    g_string_append(s, u->path);
  }
  if (u->query) {
    g_string_append(s, u->query);
  }
  if (u->fragment) {
    g_string_append(s, u->fragment);
  }

  char *result = s->str;
  g_string_free(s, FALSE);
  return result;
}

static void merge_path(uri *base, uri *r, uri *t) {
  if (g_strcmp0(base->path, "") == 0 ||
    g_strcmp0(base->path, "/") == 0 ||
    base->path == NULL)
  {
    GString *s = g_string_sized_new(strlen(r->path) + 2);
    g_string_printf(s, "/%s", r->path);
    uri_set_path(t, s->str, s->len);
    g_string_free(s, TRUE);
  } else if (r->path) {
    size_t len = strlen(base->path);
    /* NOTE: skip the last character because the path might end in /
     * but we need to skip the entire last path *segment*
     */
    char *last_slash = &base->path[len - 1];
    while (last_slash > base->path && *last_slash != '/') {
      last_slash--;
    }
    GString *s = g_string_new_len(base->path, (last_slash - base->path)+1);
    g_string_append(s, r->path);
    uri_set_path(t, s->str, s->len);
    g_string_free(s, TRUE);
  } else if (base->path) {
    uri_set_path(t, base->path, -1);
  }
}

void uri_transform(uri *base, uri *r, uri *t) {
  uri_clear(t);
  if (r->scheme) {
    uri_set_scheme(t, r->scheme, -1);
    uri_set_userinfo(t, r->userinfo, -1);
    uri_set_host(t, r->host, -1);
    t->port = r->port;
    uri_set_path(t, r->path, -1);
    remove_dot_segments(t);
    uri_set_query(t, r->query, -1);
  } else {
    /* authority */
    if (r->userinfo || r->host) {
      uri_set_userinfo(t, r->userinfo, -1);
      uri_set_host(t, r->host, -1);
      t->port = r->port;
      uri_set_path(t, r->path, -1);
      remove_dot_segments(t);
      uri_set_query(t, r->query, -1);
    } else {
      if (r->path == 0 || g_strcmp0(r->path, "") == 0) {
        uri_set_path(t, base->path, -1);
        if (r->query) {
          uri_set_query(t, r->query, -1);
        } else if (base->query) {
          uri_set_query(t, base->query, -1);
        }
      } else {
        if (r->path && g_str_has_prefix(r->path, "/")) {
          uri_set_path(t, r->path, -1);
          remove_dot_segments(t);
        } else {
          merge_path(base, r, t);
          remove_dot_segments(t);
        }
        uri_set_query(t, r->query, -1);
      }
      /* authority */
      uri_set_userinfo(t, base->userinfo, -1);
      uri_set_host(t, base->host, -1);
      t->port = base->port;
    }
    uri_set_scheme(t, base->scheme, -1);
  }
  uri_set_fragment(t, r->fragment, -1);
}

