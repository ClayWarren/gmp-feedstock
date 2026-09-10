/* Taken from the GMP Wikipedia article */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gmp.h"

#ifdef GMP_TEST_NULL_OUTPUT
static int check_null_output(void)
{
    char buffer[5] = {1, 1, 1, 1, 1};
    const char expected[5] = {8, 0, 9, 0, 1};
    char *allocated;
    void (*free_func)(void *, size_t);
    int length;

    length = gmp_sprintf(buffer, "%c%c%c", 8, 0, 9);
    if (length != 3 || memcmp(buffer, expected, sizeof(buffer)) != 0)
    {
        fprintf(stderr, "gmp_sprintf: incorrect embedded-NUL output (length %d)\n", length);
        return 1;
    }
    memset(buffer, 1, sizeof(buffer));
    length = gmp_snprintf(buffer, sizeof(buffer), "%c%c%c", 8, 0, 9);
    if (length != 3 || memcmp(buffer, expected, sizeof(buffer)) != 0)
    {
        fprintf(stderr, "gmp_snprintf: incorrect embedded-NUL output (length %d)\n", length);
        return 1;
    }
    memset(buffer, 1, sizeof(buffer));
    length = gmp_snprintf(buffer, 2, "%c%c%c", 8, 0, 9);
    if (length != 3 || buffer[0] != 8 || buffer[1] != 0 || buffer[2] != 1)
    {
        fprintf(stderr, "gmp_snprintf truncation: incorrect embedded-NUL output (length %d)\n", length);
        return 1;
    }
    length = gmp_asprintf(&allocated, "%c%c%c", 8, 0, 9);
    if (length != 3 || memcmp(allocated, expected, 4) != 0)
    {
        fprintf(stderr, "gmp_asprintf: incorrect embedded-NUL output (length %d)\n", length);
        return 1;
    }
    mp_get_memory_functions(NULL, NULL, &free_func);
    free_func(allocated, (size_t) length + 1);
    puts("GMP embedded-NUL formatted output passed");
    return 0;
}
#endif

int main(void)
{
    mpz_t x;
    mpz_t y;
    mpz_t result;

#ifdef GMP_TEST_NULL_OUTPUT
    if (check_null_output() != 0)
        return EXIT_FAILURE;
#endif

    mpz_init(x);
    mpz_init(y);
    mpz_init(result);

    mpz_set_str(x, "7612058254738945", 10);
    mpz_set_str(y, "9263591128439081", 10);

    mpz_mul(result, x, y);
    gmp_printf("\n    %Zd\n*\n    %Zd\n--------------------\n%Zd\n\n", x, y, result);

    /* free used memory */
    mpz_clear(x);
    mpz_clear(y);
    mpz_clear(result);
    return EXIT_SUCCESS;
}
