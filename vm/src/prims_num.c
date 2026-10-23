/* SmallInteger, Float and Character primitives. */
#include "core.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define INT_ARGS                                                                                                       \
    oop ro = prim_receiver(), ao = prim_argc() > 0 ? prim_arg(0) : nil_oop;                                            \
    if (!is_int(ro) || !is_int(ao)) return prim_fail();                                                               \
    int64_t a = int_val(ro), b = int_val(ao)

static void ret_int(int64_t v)
{
    if (int_fits(v)) prim_return(int_oop(v));
    else prim_fail();
}

static void ret_bool(bool b) { prim_return(b ? true_oop : false_oop); }

void p_int_add(void) { INT_ARGS; ret_int(a + b); }
void p_int_sub(void) { INT_ARGS; ret_int(a - b); }
void p_int_less(void) { INT_ARGS; ret_bool(a < b); }
void p_int_greater(void) { INT_ARGS; ret_bool(a > b); }
void p_int_less_eq(void) { INT_ARGS; ret_bool(a <= b); }
void p_int_greater_eq(void) { INT_ARGS; ret_bool(a >= b); }
void p_int_eq(void) { INT_ARGS; ret_bool(a == b); }
void p_int_not_eq(void) { INT_ARGS; ret_bool(a != b); }

void p_int_mul(void)
{
    INT_ARGS;
    int64_t r;
    if (__builtin_mul_overflow(a, b, &r)) return prim_fail();
    ret_int(r);
}

void p_int_div(void)
{
    INT_ARGS;
    if (b == 0 || a % b != 0) return prim_fail();
    ret_int(a / b);
}

void p_int_quo(void)
{
    INT_ARGS;
    if (b == 0) return prim_fail();
    ret_int(a / b);
}

void p_int_rem(void)
{
    INT_ARGS;
    if (b == 0) return prim_fail();
    ret_int(a % b);
}

void p_int_floor_div(void)
{
    INT_ARGS;
    if (b == 0) return prim_fail();
    int64_t q = a / b;
    if (a % b != 0 && ((a < 0) != (b < 0))) q--;
    ret_int(q);
}

void p_int_mod(void)
{
    INT_ARGS;
    if (b == 0) return prim_fail();
    int64_t r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) r += b;
    ret_int(r);
}

void p_int_bit_and(void) { INT_ARGS; ret_int(a & b); }
void p_int_bit_or(void) { INT_ARGS; ret_int(a | b); }
void p_int_bit_xor(void) { INT_ARGS; ret_int(a ^ b); }

void p_int_bit_shift(void)
{
    INT_ARGS;
    if (b >= 0) {
        if (a == 0) return ret_int(0);
        if (b >= 62) return prim_fail();
        int64_t r = (int64_t)((uint64_t)a << b);
        if ((r >> b) != a) return prim_fail();
        return ret_int(r);
    }
    ret_int(b <= -63 ? (a < 0 ? -1 : 0) : a >> -b);
}

void p_int_as_float(void)
{
    oop r = prim_receiver();
    if (!is_int(r)) return prim_fail();
    prim_return(float_oop((double)int_val(r)));
}

/* ---- floats ---- */

static bool num_arg(oop o, double *d)
{
    if (is_float(o)) *d = float_val(o);
    else if (is_int(o)) *d = (double)int_val(o);
    else return false;
    return true;
}

#define FLOAT_RCV                                                                                                      \
    oop ro = prim_receiver();                                                                                          \
    if (!is_float(ro)) return prim_fail();                                                                             \
    double a = float_val(ro)
#define FLOAT_ARGS                                                                                                     \
    FLOAT_RCV;                                                                                                         \
    double b;                                                                                                          \
    if (prim_argc() < 1 || !num_arg(prim_arg(0), &b)) return prim_fail()

void p_float_add(void) { FLOAT_ARGS; prim_return(float_oop(a + b)); }
void p_float_sub(void) { FLOAT_ARGS; prim_return(float_oop(a - b)); }
void p_float_mul(void) { FLOAT_ARGS; prim_return(float_oop(a * b)); }
void p_float_div(void)
{
    FLOAT_ARGS;
    if (b == 0.0) return prim_fail();
    prim_return(float_oop(a / b));
}
void p_float_less(void) { FLOAT_ARGS; ret_bool(a < b); }
void p_float_greater(void) { FLOAT_ARGS; ret_bool(a > b); }
void p_float_less_eq(void) { FLOAT_ARGS; ret_bool(a <= b); }
void p_float_greater_eq(void) { FLOAT_ARGS; ret_bool(a >= b); }
void p_float_eq(void) { FLOAT_ARGS; ret_bool(a == b); }
void p_float_not_eq(void) { FLOAT_ARGS; ret_bool(a != b); }

void p_float_truncated(void)
{
    FLOAT_RCV;
    double t = trunc(a);
    if (!(t >= -4611686018427387904.0 && t < 4611686018427387904.0)) return prim_fail();
    prim_return(int_oop((int64_t)t));
}

void p_float_fraction_part(void)
{
    FLOAT_RCV;
    double ip;
    prim_return(float_oop(modf(a, &ip)));
}

void p_float_exponent(void)
{
    FLOAT_RCV;
    if (a == 0.0 || !isfinite(a)) return prim_return(int_oop(0));
    prim_return(int_oop(ilogb(a)));
}

void p_float_times_two_power(void)
{
    FLOAT_RCV;
    oop e = prim_argc() > 0 ? prim_arg(0) : nil_oop;
    if (!is_int(e)) return prim_fail();
    int64_t n = int_val(e);
    if (n > 100000) n = 100000;
    if (n < -100000) n = -100000;
    prim_return(float_oop(ldexp(a, (int)n)));
}

void p_float_sqrt(void) { FLOAT_RCV; prim_return(float_oop(sqrt(a))); }
void p_float_abs(void) { FLOAT_RCV; prim_return(float_oop(fabs(a))); }
void p_float_sin(void) { FLOAT_RCV; prim_return(float_oop(sin(a))); }
void p_float_cos(void) { FLOAT_RCV; prim_return(float_oop(cos(a))); }
void p_float_arctan(void) { FLOAT_RCV; prim_return(float_oop(atan(a))); }
void p_float_ln(void) { FLOAT_RCV; prim_return(float_oop(log(a))); }
void p_float_exp(void) { FLOAT_RCV; prim_return(float_oop(exp(a))); }

/* Shortest round-trip decimal: "123.0", "0.1", "1.0e-10", "-2.5e100", "inf", "-inf", "nan". */
void p_float_print_string(void)
{
    FLOAT_RCV;
    char out[64];
    if (isnan(a)) strcpy(out, "nan");
    else if (isinf(a)) strcpy(out, a < 0 ? "-inf" : "inf");
    else if (a == 0.0) strcpy(out, signbit(a) ? "-0.0" : "0.0");
    else {
        char buf[40];
        for (int p = 1; p <= 17; p++) {
            snprintf(buf, sizeof buf, "%.*e", p - 1, a);
            if (strtod(buf, NULL) == a) break;
        }
        bool neg = buf[0] == '-';
        char *s = buf + neg, digits[24];
        int nd = 0;
        for (; *s && *s != 'e'; s++)
            if (*s != '.') digits[nd++] = *s;
        while (nd > 1 && digits[nd - 1] == '0') nd--;
        digits[nd] = 0;
        int exp = atoi(s + 1);
        char *o = out;
        if (neg) *o++ = '-';
        if (exp >= -5 && exp < 16) {
            if (exp < 0) {
                o += sprintf(o, "0.");
                for (int i = 0; i < -exp - 1; i++) *o++ = '0';
                o += sprintf(o, "%s", digits);
            } else {
                for (int i = 0; i <= exp; i++) *o++ = i < nd ? digits[i] : '0';
                *o++ = '.';
                if (nd > exp + 1) o += sprintf(o, "%s", digits + exp + 1);
                else *o++ = '0';
            }
            *o = 0;
        } else {
            *o++ = digits[0];
            *o++ = '.';
            if (nd > 1) o += sprintf(o, "%s", digits + 1);
            else *o++ = '0';
            sprintf(o, "e%d", exp);
        }
    }
    prim_return(string_from_utf8(out, strlen(out)));
}

void p_float_as_ieee_bits(void)
{
    FLOAT_RCV;
    uint64_t b;
    memcpy(&b, &a, 8);
    prim_return(b <= (uint64_t)VM_INT_MAX ? int_oop((int64_t)b) : large_int_from_u64(b, false));
}

void p_float_from_ieee_bits(void)
{
    uint64_t b;
    if (prim_argc() < 1 || !u64_of(prim_arg(0), &b)) return prim_fail();
    double d;
    memcpy(&d, &b, 8);
    prim_return(float_oop(d));
}

/* ---- characters ---- */

void p_char_value(void)
{
    oop r = prim_receiver();
    if (!is_char(r)) return prim_fail();
    prim_return(int_oop(char_val(r)));
}

void p_char_from_value(void)
{
    oop v = prim_argc() > 0 ? prim_arg(0) : nil_oop;
    if (!is_int(v) || int_val(v) < 0 || int_val(v) > 0x3FFFFFFF) return prim_fail();
    prim_return(char_oop((uint32_t)int_val(v)));
}
