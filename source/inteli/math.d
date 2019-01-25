/**
* Transcendental function on 4 numbers at once.
*
* Copyright: Copyright Auburn Sounds 2016-2018.
*            Copyright (C) 2007  Julien Pommier
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module inteli.math;

/* Copyright (C) 2007  Julien Pommier

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.

  (this is the zlib license)
*/
import inteli.emmintrin;
import inteli.internals;

static immutable __m128 _ps_1   = [1.0f, 1.0f, 1.0f, 1.0f];
static immutable __m128 _ps_0p5 = [0.5f, 0.5f, 0.5f, 0.5f];

/* the smallest non denormalized float number */
static immutable __m128i _psi_min_norm_pos  = [0x00800000,   0x00800000,   0x00800000, 0x00800000];

static immutable __m128i _pi32_0x7f = [0x7f, 0x7f, 0x7f, 0x7f];


/// Natural logarithm computed for 4 simultaneous float.
/// This is an approximation, valid up to approximately -119dB of accuracy
/// IMPORTANT: NaN, zero, or infinity input not supported properly. x must be > 0.
__m128 _mm_log_ps(__m128 x)
{
    static immutable __m128i _psi_inv_mant_mask = [~0x7f800000, ~0x7f800000, ~0x7f800000, ~0x7f800000];
    static immutable __m128 _ps_cephes_SQRTHF = [0.707106781186547524, 0.707106781186547524, 0.707106781186547524, 0.707106781186547524];
    static immutable __m128 _ps_cephes_log_p0 = [7.0376836292E-2, 7.0376836292E-2, 7.0376836292E-2, 7.0376836292E-2];
    static immutable __m128 _ps_cephes_log_p1 = [- 1.1514610310E-1, - 1.1514610310E-1, - 1.1514610310E-1, - 1.1514610310E-1];
    static immutable __m128 _ps_cephes_log_p2 = [1.1676998740E-1, 1.1676998740E-1, 1.1676998740E-1, 1.1676998740E-1];
    static immutable __m128 _ps_cephes_log_p3 = [- 1.2420140846E-1, - 1.2420140846E-1, - 1.2420140846E-1, - 1.2420140846E-1];
    static immutable __m128 _ps_cephes_log_p4 = [+ 1.4249322787E-1, + 1.4249322787E-1, + 1.4249322787E-1, + 1.4249322787E-1];
    static immutable __m128 _ps_cephes_log_p5 = [- 1.6668057665E-1, - 1.6668057665E-1, - 1.6668057665E-1, - 1.6668057665E-1];
    static immutable __m128 _ps_cephes_log_p6 = [+ 2.0000714765E-1, + 2.0000714765E-1, + 2.0000714765E-1, + 2.0000714765E-1];
    static immutable __m128 _ps_cephes_log_p7 = [- 2.4999993993E-1, - 2.4999993993E-1, - 2.4999993993E-1, - 2.4999993993E-1];
    static immutable __m128 _ps_cephes_log_p8 = [+ 3.3333331174E-1, + 3.3333331174E-1, + 3.3333331174E-1, + 3.3333331174E-1];
    static immutable __m128 _ps_cephes_log_q1 = [-2.12194440e-4, -2.12194440e-4, -2.12194440e-4, -2.12194440e-4];
    static immutable __m128 _ps_cephes_log_q2 = [0.693359375, 0.693359375, 0.693359375, 0.693359375];

    __m128i emm0;
    __m128 one = _ps_1;
    __m128 invalid_mask = _mm_cmple_ps(x, _mm_setzero_ps());
    x = _mm_max_ps(x, cast(__m128)_psi_min_norm_pos);  /* cut off denormalized stuff */
    emm0 = _mm_srli_epi32(_mm_castps_si128(x), 23);

    /* keep only the fractional part */
    x = _mm_and_ps(x, cast(__m128)_psi_inv_mant_mask);
    x = _mm_or_ps(x, _ps_0p5);

    emm0 = _mm_sub_epi32(emm0, cast(__m128i)_pi32_0x7f);
    __m128 e = _mm_cvtepi32_ps(emm0);
    e += one;
    __m128 mask = _mm_cmplt_ps(x, _ps_cephes_SQRTHF);
    __m128 tmp = _mm_and_ps(x, mask);
    x -= one;
    e -= _mm_and_ps(one, mask);
    x += tmp;
    __m128 z = x * x;
    __m128 y = _ps_cephes_log_p0;
    y *= x;
    y += _ps_cephes_log_p1;
    y *= x;
    y += _ps_cephes_log_p2;
    y *= x;
    y += _ps_cephes_log_p3;
    y *= x;
    y += _ps_cephes_log_p4;
    y *= x;
    y += _ps_cephes_log_p5;
    y *= x;
    y += _ps_cephes_log_p6;
    y *= x;
    y += _ps_cephes_log_p7;
    y *= x;
    y += _ps_cephes_log_p8;
    y *= x;
    y *= z;
    tmp = e * _ps_cephes_log_q1;
    y += tmp;
    tmp = z * _ps_0p5;
    y = y - tmp;
    tmp = e * _ps_cephes_log_q2;
    x += y;
    x += tmp;
    x = _mm_or_ps(x, invalid_mask); // negative arg will be NAN
    return x;
}

/// Natural exp computed for 4 simultaneous float.
/// This is an approximation, valid up to approximately -109dB of accuracy
/// IMPORTANT: NaN input not supported.
__m128 _mm_exp_ps(__m128 x) 
{
    static immutable __m128 _ps_exp_hi         = [88.3762626647949f, 88.3762626647949f, 88.3762626647949f, 88.3762626647949f];
    static immutable __m128 _ps_exp_lo         = [-88.3762626647949f, -88.3762626647949f, -88.3762626647949f, -88.3762626647949f];
    static immutable __m128 _ps_cephes_LOG2EF  = [1.44269504088896341, 1.44269504088896341, 1.44269504088896341, 1.44269504088896341];
    static immutable __m128 _ps_cephes_exp_C1  = [0.693359375, 0.693359375, 0.693359375, 0.693359375];
    static immutable __m128 _ps_cephes_exp_C2  = [-2.12194440e-4, -2.12194440e-4, -2.12194440e-4, -2.12194440e-4];
    static immutable __m128 _ps_cephes_exp_p0  = [1.9875691500E-4, 1.9875691500E-4, 1.9875691500E-4, 1.9875691500E-4];
    static immutable __m128 _ps_cephes_exp_p1  = [1.3981999507E-3, 1.3981999507E-3, 1.3981999507E-3, 1.3981999507E-3];
    static immutable __m128 _ps_cephes_exp_p2  = [8.3334519073E-3, 8.3334519073E-3, 8.3334519073E-3, 8.3334519073E-3];
    static immutable __m128 _ps_cephes_exp_p3  = [4.1665795894E-2, 4.1665795894E-2, 4.1665795894E-2, 4.1665795894E-2];
    static immutable __m128 _ps_cephes_exp_p4  = [1.6666665459E-1, 1.6666665459E-1, 1.6666665459E-1, 1.6666665459E-1];
    static immutable __m128 _ps_cephes_exp_p5  = [5.0000001201E-1, 5.0000001201E-1, 5.0000001201E-1, 5.0000001201E-1];

    __m128 tmp = _mm_setzero_ps(), fx;
    __m128i emm0;
    __m128 one = _ps_1;

    x = _mm_min_ps(x, _ps_exp_hi);
    x = _mm_max_ps(x, _ps_exp_lo);

    /* express exp(x) as exp(g + n*log(2)) */
    fx = x * _ps_cephes_LOG2EF;
    fx += _ps_0p5;

    /* how to perform a floorf with SSE: just below */
    emm0 = _mm_cvttps_epi32(fx);
    tmp  = _mm_cvtepi32_ps(emm0);

    /* if greater, substract 1 */
    __m128 mask = _mm_cmpgt_ps(tmp, fx);    
    mask = _mm_and_ps(mask, one);
    fx = tmp - mask;

    tmp = fx * _ps_cephes_exp_C1;
    __m128 z = fx * _ps_cephes_exp_C2;
    x -= tmp;
    x -= z;

    z = x * x;

    __m128 y = _ps_cephes_exp_p0;
    y *= x;
    y += _ps_cephes_exp_p1;
    y *= x;
    y += _ps_cephes_exp_p2;
    y *= x;
    y += _ps_cephes_exp_p3;
    y *= x;
    y += _ps_cephes_exp_p4;
    y *= x;
    y += _ps_cephes_exp_p5;
    y *= z;
    y += x;
    y += one;

    /* build 2^n */
    emm0 = _mm_cvttps_epi32(fx);
    emm0 = _mm_add_epi32(emm0, cast(__m128i)_pi32_0x7f);
    emm0 = _mm_slli_epi32(emm0, 23);
    __m128 pow2n = _mm_castsi128_ps(emm0);
    y = _mm_mul_ps(y, pow2n);
    return y;
}

static immutable __m128 _ps_minus_cephes_DP1 = [-0.78515625, -0.78515625, -0.78515625, -0.78515625];
static immutable __m128 _ps_minus_cephes_DP2 = [-2.4187564849853515625e-4, -2.4187564849853515625e-4, -2.4187564849853515625e-4, -2.4187564849853515625e-4];
static immutable __m128 _ps_minus_cephes_DP3 = [-3.77489497744594108e-8, -3.77489497744594108e-8, -3.77489497744594108e-8, -3.77489497744594108e-8];
static immutable __m128 _ps_sincof_p0        = [-1.9515295891E-4, -1.9515295891E-4, -1.9515295891E-4, -1.9515295891E-4];
static immutable __m128 _ps_sincof_p1        = [ 8.3321608736E-3,  8.3321608736E-3,  8.3321608736E-3,  8.3321608736E-3];
static immutable __m128 _ps_sincof_p2        = [-1.6666654611E-1, -1.6666654611E-1, -1.6666654611E-1, -1.6666654611E-1];
static immutable __m128 _ps_coscof_p0        = [ 2.443315711809948E-005,  2.443315711809948E-005,  2.443315711809948E-005,  2.443315711809948E-005];
static immutable __m128 _ps_coscof_p1        = [-1.388731625493765E-003, -1.388731625493765E-003, -1.388731625493765E-003, -1.388731625493765E-003];
static immutable __m128 _ps_coscof_p2        = [ 4.166664568298827E-002,  4.166664568298827E-002,  4.166664568298827E-002,  4.166664568298827E-002];
static immutable __m128 _ps_cephes_FOPI      = [ 1.27323954473516,  1.27323954473516,  1.27323954473516,  1.27323954473516];


unittest
{
    import std.math;

    bool approxEquals(double groundTruth, double approx, double epsilon)
    {
        if (!isFinite(groundTruth))
            return true; // no need to approximate where this is NaN or infinite

        if (groundTruth == 0) // the approximaton should produce zero too if needed
        {
            return approx == 0;
        }

        if (approx == 0)
        {
            // If the approximation produces zero, the error should be below 140 dB
            return ( abs(groundTruth) < 1e-7 );
        }

        if ( ( abs(groundTruth / approx) - 1 ) >= epsilon)
        {
            import std.stdio;
            writeln(abs(groundTruth / approx) - 1 );
        }

        return ( abs(groundTruth / approx) - 1 ) < epsilon;
    }

    // test _mm_log_ps
    for (double mantissa = 0.1; mantissa < 1.0; mantissa += 0.005)
    {
        foreach (exponent; -23..23)
        {
            double x = mantissa * 2.0 ^^ exponent;
            double phobosValue = log(x);
            __m128 v = _mm_log_ps(_mm_set1_ps(x));
            foreach(i; 0..4)
                assert(approxEquals(phobosValue, v[i], 1.1e-6));
        }
    }

    // test _mm_exp_ps    
    for (double mantissa = -1.0; mantissa < 1.0; mantissa += 0.01)
    {
        foreach (exponent; -23..23)
        {
            double x = mantissa * 2.0 ^^ exponent;

            // don't test too high numbers because they saturate FP precision pretty fast
            if (x > 50) continue;

            double phobosValue = exp(x);
            __m128 v = _mm_exp_ps(_mm_set1_ps(x));
            foreach(i; 0..4)
               assert(approxEquals(phobosValue, v[i], 3.4e-6));
        }
    }

    // test than exp(-inf) is 0
    {
        __m128 R = _mm_exp_ps(_mm_set1_ps(-float.infinity));
        float[4] correct = [0.0f, 0.0f, 0.0f, 0.0f];
        assert(R.array == correct);
    }

    // test log baheviour with NaN and infinities
    // the only guarantee for now is that _mm_log_ps(negative) yield a NaN
    {
        __m128 R = _mm_log_ps(_mm_setr_ps(+0.0f, -0.0f, -1.0f, float.nan));
      // DOESN'T PASS
      //  assert(isInfinity(R[0]) && R[0] < 0); // log(+0.0f) = -infinity
      // DOESN'T PASS
      //  assert(isInfinity(R[1]) && R[1] < 0); // log(-0.0f) = -infinity
        assert(isNaN(R[2])); // log(negative number) = NaN

        // DOESN'T PASS
        //assert(isNaN(R[3])); // log(NaN) = NaN
    }
}