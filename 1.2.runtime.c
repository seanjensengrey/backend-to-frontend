#include <stdio.h>

extern int scheme_entry(void);

/* define all scheme constatns */
#define	bool_f		0x2f
#define	bool_t		0x6f
#define	fx_mask		0x03
#define	fx_tag		0x00
#define	fx_shift	2
#define	nullval		0x3f
#define	char_mask	0xff
#define	char_shift	8
#define	char_tag	0x0f

/* all scheme values are of type ptrs */
typedef unsigned int ptr;

static void print_ptr(ptr x) {
	if ((x & fx_mask) == fx_tag) {
		printf("%d", ((int)x) >> fx_shift);
	} else if (x == bool_f) {
		printf("#f");
	} else if (x == bool_t) {
		printf("#t");
	} else if (x == nullval) {
		printf("()");
	} else if ((x & char_mask) == char_tag) {
		int c = x >> char_shift;
		switch (c) {
		default:	printf("#\\%c", c);	break;
		case '\t':	printf("#\\tab");	break;
		case '\n':	printf("#\\newline");	break;
		case '\r':	printf("#\\return");	break;
		case ' ':	printf("#\\space");	break;
		}
	} else {
		printf("#<unknown #0x%08x>", x);
	}
	printf("\n");
}

int main(int argc, char** argv) {
	print_ptr(scheme_entry());
	return 0;
}
