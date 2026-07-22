
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <linux/filter.h>
#include <kafel.h>

static void print_bpf(const struct sock_fprog *prog) {
	printf("%hu\n", prog->len);
	for (unsigned short i = 0; i < prog->len; i++) {
		printf("%hu %hhu %hhu %u\n",
			prog->filter[i].code,
			prog->filter[i].jt,
			prog->filter[i].jf,
			prog->filter[i].k
		);
	}
}
static void dump_bpf(const struct sock_fprog *prog) {
	fwrite(prog->filter, sizeof(*prog->filter), prog->len, stdout);
}

int main(void) {
	size_t len = 0, cap = 65536;
	char *buf = malloc(cap);
	if (!buf) { fputs("malloc failed\n", stderr); return 1; }

	/* Read all of stdin into buf */
	size_t total = 0;
	int c;
	while ((c = getchar()) != EOF) {
		if (total + 1 >= cap) {
			cap *= 2;
			char *tmp = realloc(buf, cap);
			if (!tmp) { fputs("realloc failed\n", stderr); free(buf); return 1; }
			buf = tmp;
		}
		buf[total++] = (char)c;
	}
	buf[total] = '\0';

	struct sock_fprog prog;
	int ret = kafel_compile_string(buf, &prog);
	free(buf);

	if (ret) {
		fputs("kafel compilation failed\n", stderr);
		return 1;
	}

	dump_bpf(&prog);
	free(prog.filter);
	return 0;
}
