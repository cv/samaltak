/* CLBG mandelbrot as AWFY's Mandelbrot (Mandelbrot.st), size 500: the XOR of the bitmap's bytes. */
#define NAME "Mandelbrot"
#define EXPECTED 191
#include "harness.h"

static int64_t setup(void) { return 0; }

static int64_t run(void)
{
    const int size = 500;
    int64_t sum = 0, byte_acc = 0, bit_num = 0;
    for (int y = 0; y < size; y++) {
        double ci = (2.0 * y / size) - 1.0;
        for (int x = 0; x < size; x++) {
            double zrzr = 0.0, zi = 0.0, zizi = 0.0, cr = (2.0 * x / size) - 1.5;
            int z = 0, not_done = 1, escape = 0;
            while (not_done && z < 50) {
                double zr = zrzr - zizi + cr;
                zi = 2.0 * zr * zi + ci;
                zrzr = zr * zr;
                zizi = zi * zi;
                if (zrzr + zizi > 4.0) {
                    not_done = 0;
                    escape = 1;
                }
                z++;
            }
            byte_acc = (byte_acc << 1) + escape;
            bit_num++;
            if (bit_num == 8) {
                sum ^= byte_acc;
                byte_acc = 0;
                bit_num = 0;
            } else if (x == size - 1) {
                byte_acc <<= 8 - bit_num;
                sum ^= byte_acc;
                byte_acc = 0;
                bit_num = 0;
            }
        }
    }
    return sum;
}
