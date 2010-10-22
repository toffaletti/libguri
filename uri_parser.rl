#include "uri_parser.h"
#include <stdlib.h>
#include <assert.h>
#include <ctype.h>
#include <string.h>

#include <stdio.h>

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

static void normalize_path(uri *u) {
  size_t plen = strlen(u->path);
  switch (plen) {
    case 0:
#ifdef URI_USE_GLIB
      u->path = g_string_chunk_insert(u->chunk, "/");
#else
      u->path = strdup("/");
#endif
      return;
    case 1:
      return;
  }
  size_t segs_size = (plen / 2) * sizeof(char *);
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
          /* terminate the segment with null */
          *p = 0;
          /* switch on length of segment */
          switch (p-(segb+1)) {
            case 1:
              /* skip . path segments */
              if (*(segb+1) == '.') goto next;
              break;
            case 2:
              /* rewind for .. path segments */
              if (*(segb+1) == '.' && *(segb+2) == '.') {
                if (segm) segm--;
                goto next;
              }
              break;
          }
          /* put the pointer to the segment in segments array */
          segs[segm] = segb+1;
          segm++;
        }
  next:
        /* move begin pointer forward. reset end pointer to 0 */
        segb = p;
      }
    }
    /* final segment */
    if (segb+1 < u->path + plen) {
      segs[segm] = segb+1;
      segm++;
    }

    /* reassemble path from segment pointers */
    p = u->path;
    for (unsigned int segi = 0; segi < segm; segi++) {
      *p = '/'; p++;
      char *pn = segs[segi];
      while (*pn) {
        *p = *pn;
        p++;
        pn++;
      }
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
  normalize_path(u);

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
    g_string_append_printf(s, "%s://", u->scheme);
  }
  if (u->userinfo) {
    g_string_append_printf(s, "%s@", u->userinfo);
  }
  if (u->host) {
    g_string_append(s, u->host);
  }
  if (u->port) {
    g_string_append_printf(s, ":%u", u->port);
  }
  if (u->path) {
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

