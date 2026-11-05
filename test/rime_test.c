/*
 * Minimal Rime console for testing a schema without an input method.
 *
 *   rime_test [-u user_dir] [-s schema] [keys ...]
 *
 * Each argument (or each input line, when none are given) is fed to
 * RimeSimulateKeySequence, so plain letters, digits and {space},
 * {Page_Down}, {BackSpace}, {Escape} ... all work. After each one it prints
 * any committed text, the preedit and the current candidate page.
 * Learning (the user dictionary) persists in user_dir between runs.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <rime_api.h>

static RimeApi *rime;

#define COUNT_LIMIT 2000

/*
 * Rime reports only the page number and "last page", so walk the whole
 * candidate list to count it. Capped: one letter with completion on can
 * match thousands. Returns -1 when the cap was reached.
 */
static int count_candidates(RimeSessionId session)
{
	RimeCandidateListIterator iter = { 0 };
	int n = 0;

	if (!rime->candidate_list_begin(session, &iter))
		return 0;
	while (rime->candidate_list_next(&iter)) {
		if (++n >= COUNT_LIMIT) {
			n = -1;
			break;
		}
	}
	rime->candidate_list_end(&iter);
	return n;
}

static void show(RimeSessionId session)
{
	RIME_STRUCT(RimeCommit, commit);
	RIME_STRUCT(RimeContext, ctx);
	int i;

	if (rime->get_commit(session, &commit)) {
		printf("commit: %s\n", commit.text);
		rime->free_commit(&commit);
	}
	if (!rime->get_context(session, &ctx))
		return;
	if (ctx.composition.length > 0)
		printf("input:  %s\n", ctx.composition.preedit);
	/* a menu with no input: e.g. associated phrases after a commit */
	if (ctx.composition.length > 0 || ctx.menu.num_candidates > 0) {
		int total = count_candidates(session);
		int size = ctx.menu.page_size > 0 ? ctx.menu.page_size : 1;

		if (total < 0)
			printf("page %d/%d+:", ctx.menu.page_no + 1, COUNT_LIMIT / size);
		else
			printf("page %d/%d:", ctx.menu.page_no + 1,
			       total ? (total + size - 1) / size : 1);
		for (i = 0; i < ctx.menu.num_candidates; i++) {
			RimeCandidate *c = &ctx.menu.candidates[i];

			printf(" %d.%s%s%s", i + 1, c->text,
			       c->comment ? "~" : "", c->comment ? c->comment : "");
		}
		printf("\n");
	}
	rime->free_context(&ctx);
}

/* Terminal escape sequences for keys people press out of habit. */
static const struct {
	const char *seq;
	const char *name;
} term_keys[] = {
	{ "\033[5~", "{Page_Up}" },
	{ "\033[6~", "{Page_Down}" },
	{ "\033[A", "{Up}" },
	{ "\033[B", "{Down}" },
	{ "\033[C", "{Right}" },
	{ "\033[D", "{Left}" },
	{ "\033", "{Escape}" },         /* a lone Esc, after the longer ones */
};

static void translate_term_keys(const char *in, char *out, size_t size)
{
	size_t n = 0, i;

	while (*in && n + 1 < size) {
		for (i = 0; i < sizeof(term_keys) / sizeof(term_keys[0]); i++) {
			size_t len = strlen(term_keys[i].seq);

			if (!strncmp(in, term_keys[i].seq, len))
				break;
		}
		if (i < sizeof(term_keys) / sizeof(term_keys[0])) {
			size_t len = strlen(term_keys[i].name);

			if (n + len + 1 > size)
				break;
			memcpy(out + n, term_keys[i].name, len);
			n += len;
			in += strlen(term_keys[i].seq);
		} else {
			out[n++] = *in++;
		}
	}
	out[n] = '\0';
}

static void feed(RimeSessionId session, const char *line)
{
	char keys[4096];

	translate_term_keys(line, keys, sizeof(keys));
	printf("> %s\n", keys);
	if (!rime->simulate_key_sequence(session, keys))
		printf("(keys not handled)\n");
	show(session);
}

int main(int argc, char **argv)
{
	const char *user_dir = "/rime";
	const char *schema = "mixed_quick";
	char line[1024];
	RimeSessionId session;
	int opt, i;

	while ((opt = getopt(argc, argv, "u:s:")) != -1) {
		switch (opt) {
		case 'u':
			user_dir = optarg;
			break;
		case 's':
			schema = optarg;
			break;
		default:
			fprintf(stderr, "usage: %s [-u user_dir] [-s schema] [keys ...]\n", argv[0]);
			return 2;
		}
	}

	rime = rime_get_api();
	RIME_STRUCT(RimeTraits, traits);
	traits.shared_data_dir = "/usr/share/rime-data";
	traits.user_data_dir = user_dir;
	traits.log_dir = "";            /* log to stderr only */
	traits.min_log_level = 2;       /* errors */
	traits.distribution_name = "rime_test";
	traits.distribution_code_name = "rime_test";
	traits.distribution_version = "0.1";
	traits.app_name = "rime.rime_test";

	rime->setup(&traits);
	rime->initialize(NULL);
	/* deploys (compiles the dictionaries) when the sources changed */
	if (rime->start_maintenance(True))
		rime->join_maintenance_thread();

	session = rime->create_session();
	if (!session || !rime->select_schema(session, schema)) {
		fprintf(stderr, "cannot select schema %s\n", schema);
		rime->finalize();
		return 1;
	}

	if (optind < argc) {
		for (i = optind; i < argc; i++)
			feed(session, argv[i]);
	} else {
		printf("schema %s ready; type keys, e.g. hi, {space}, 3, {Page_Down}, "
		       "{Escape}; Ctrl-D quits\n", schema);
		while (fgets(line, sizeof(line), stdin)) {
			line[strcspn(line, "\n")] = '\0';
			if (line[0])
				feed(session, line);
		}
	}

	rime->destroy_session(session);
	rime->finalize();               /* flushes the user dictionary */
	return 0;
}
