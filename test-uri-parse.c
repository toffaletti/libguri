#include "uri_parser.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>


/* TODO: steal test uris from:
 * http://code.google.com/p/google-url/source/browse/trunk/src/gurl_unittest.cc
 */

static void test_uri_parse_long(void) {
  static const char uri1[] = "http://www.google.com/images?hl=en&client=firefox-a&hs=tld&rls=org.mozilla:en-US:official&q=philippine+hijacked+bus+pictures&um=1&ie=UTF-8&source=univ&ei=SC-_TLbjE5H2tgO70PHODA&sa=X&oi=image_result_group&ct=title&resnum=1&ved=0CCIQsAQwAA&biw=1239&bih=622";

  uri u;
  uri_init(&u);
  g_assert(uri_parse(&u, uri1, strlen(uri1), NULL));
  uri_free(&u);
}

static void test_uri_compose(void) {
  static const char uri1[] = "eXAMPLE://ExAmPlE.CoM/foo/../boo/%25hi%0b/.t%65st/./this?query=string#frag";

  uri u;
  uri_init(&u);
  g_assert(uri_parse(&u, uri1, strlen(uri1), NULL));
  uri_normalize(&u);
  char *s = uri_compose(&u);
  g_assert(g_strcmp0("example://example.com/boo/%25hi%0B/.test/this?query=string#frag", s) == 0);
  free(s);
  uri_free(&u);
}

static void test_uri_normalize_host(void) {
  static const char uri1[] = "eXAMPLE://ExAmPlE.CoM/";

  uri u;
  uri_init(&u);
  g_assert(uri_parse(&u, uri1, strlen(uri1), NULL));
  uri_normalize(&u);
  g_assert(g_strcmp0("example.com", u.host) == 0);

  uri_free(&u);
}

static void test_uri_normalize_one_slash(void) {
  static const char uri1[] = "eXAMPLE://a";
  static const char uri2[] = "eXAMPLE://a/";

  uri u;
  uri_init(&u);
  g_assert(uri_parse(&u, uri1, strlen(uri1), NULL));
  uri_normalize(&u);
  g_assert(g_strcmp0("/", u.path) == 0);

  uri_clear(&u);

  g_assert(uri_parse(&u, uri2, strlen(uri2), NULL));
  uri_normalize(&u);
  g_assert(g_strcmp0("/", u.path) == 0);

  uri_free(&u);
}

static void test_uri_normalize_all_slashes(void) {
  static const char uri1[] = "eXAMPLE://a//////";

  uri u;
  uri_init(&u);
  g_assert(uri_parse(&u, uri1, strlen(uri1), NULL));
  uri_normalize(&u);
  g_assert(g_strcmp0("/", u.path) == 0);
  uri_free(&u);
}

static void test_uri_normalize(void) {
  static const char uri1[] = "eXAMPLE://a/./b/../b/%63/%7bfoo%7d";

  uri u;
  uri_init(&u);
  g_assert(uri_parse(&u, uri1, strlen(uri1), NULL));
  uri_normalize(&u);
  g_assert(g_strcmp0("/b/c/%7Bfoo%7D", u.path) == 0);
  uri_clear(&u);

  static const char uri2[] = "http://host/../";
  g_assert(uri_parse(&u, uri2, strlen(uri2), NULL));
  uri_normalize(&u);
  g_assert(g_strcmp0(u.path, "/") == 0);
  uri_clear(&u);

  static const char uri3[] = "http://host/./";
  g_assert(uri_parse(&u, uri3, strlen(uri3), NULL));
  uri_normalize(&u);
  g_assert(g_strcmp0("/", u.path) == 0);

  uri_free(&u);
}

static void test_uri_parse_many(void) {
  uri u;

  uri_init(&u);

  const char uri1[] = "http://example.com/path/to/something?query=string#frag";
  g_assert(uri_parse(&u, uri1, strlen(uri1), NULL));
  g_assert(g_strcmp0(u.scheme, "http") == 0);
  g_assert(g_strcmp0(u.host, "example.com") == 0);
  g_assert(g_strcmp0(u.path, "/path/to/something") == 0);
  g_assert(g_strcmp0(u.query, "?query=string") == 0);
  g_assert(g_strcmp0(u.fragment, "#frag") == 0);
  uri_clear(&u);

  const char uri2[] = "http://jason:password@example.com:5555/path/to/";
  g_assert(uri_parse(&u, uri2, strlen(uri2), NULL));
  g_assert(g_strcmp0(u.scheme, "http") == 0);
  g_assert(g_strcmp0(u.userinfo, "jason:password") == 0);
  g_assert(g_strcmp0(u.host, "example.com") == 0);
  g_assert(u.port == 5555);
  g_assert(g_strcmp0(u.path, "/path/to/") == 0);
  uri_clear(&u);

  /* this should fail */
  const char uri3[] = "http://baduri;f[303fds";
  const char *error_at = NULL;
  g_assert(uri_parse(&u, uri3, strlen(uri3), &error_at) == 0);
  g_assert(error_at != NULL);
  g_assert(g_strcmp0("[303fds", error_at) == 0);
  uri_clear(&u);

  const char uri4[] = "https://example.com:23999";
  g_assert(uri_parse(&u, uri4, strlen(uri4), &error_at));
  g_assert(g_strcmp0(u.scheme, "https") == 0);
  g_assert(g_strcmp0(u.host, "example.com") == 0);
  g_assert(u.port == 23999);
  /* TODO: maybe make empty path == NULL? */
  g_assert(g_strcmp0(u.path, "") == 0);
  g_assert(u.query == NULL);
  g_assert(u.fragment == NULL);
  g_assert(error_at == NULL);
  uri_clear(&u);

  const char uri5[] = "svn+ssh://jason:password@example.com:22/thing/and/stuff";
  g_assert(uri_parse(&u, uri5, strlen(uri5), &error_at));
  g_assert(g_strcmp0(u.scheme, "svn+ssh") == 0);
  g_assert(g_strcmp0(u.userinfo, "jason:password") == 0);
  g_assert(g_strcmp0(u.host, "example.com") == 0);
  g_assert(u.port == 22);
  g_assert(g_strcmp0(u.path, "/thing/and/stuff") == 0);
  g_assert(error_at == NULL);
  uri_clear(&u);

  uri_free(&u);
}

int main(int argc, char *argv[]) {
  g_test_init(&argc, &argv, NULL);
  g_test_add_func("/uri_parse/many", test_uri_parse_many);
  g_test_add_func("/uri_parse/long", test_uri_parse_long);
  g_test_add_func("/uri_parse/normalize", test_uri_normalize);
  g_test_add_func("/uri_parse/normalize/all_slashes", test_uri_normalize_all_slashes);
  g_test_add_func("/uri_parse/normalize/one_slash", test_uri_normalize_one_slash);
  g_test_add_func("/uri_parse/normalize/host", test_uri_normalize_host);
  g_test_add_func("/uri_parse/compose", test_uri_compose);
  return g_test_run();
}
