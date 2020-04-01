#include <stdint.h>
#include <stddef.h>

void base16_encode(char *outbuf, char *inbuf, size_t in_length) {
    const char *chartab = "0123456789abcdef";
    for (size_t i = 0; i < in_length; i++) {
        uint8_t c = inbuf[i];
        outbuf[2 * i] = chartab[(c & 0xf0) >> 4];
        outbuf[2 * i + 1] = chartab[c & 0x0f];
    }
}
