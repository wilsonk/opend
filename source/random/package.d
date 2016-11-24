/++
Authors: Ilya Yaroshenko
Copyright: Copyright, Ilya Yaroshenko 2016-.
License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+/
module random;

import std.traits;

public import random.engine;

/++
Params:
    gen = saturated random number generator
Returns:
    Uniformly distributed integer for interval `[0 .. T.max]`.
+/
T rand(T, G)(ref G gen)
    if (isSaturatedRandomEngine!G && isIntegral!T && !is(T == enum))
{
    alias R = ReturnType!G;
    enum P = T.sizeof / R.sizeof;
    static if (P > 1)
    {
        T ret = void;
        foreach(p; 0..P)
            (cast(R*)(&ret))[p] = gen();
        return ret;
    }
    else
    {
        version(LDC) pragma(inline, true);
        return cast(T) gen();
    }
}

///
unittest
{
    import random.engine.xorshift;
    auto gen = Xorshift(1);
    auto s = gen.rand!short;
    auto n = gen.rand!ulong;
}

/++
Params:
    gen = saturated random number generator
Returns:
    Uniformly distributed boolean.
+/
bool rand(T : bool, G)(ref G gen)
    if (isSaturatedRandomEngine!G)
{
    return gen() & 1;
}

///
unittest
{
    import random.engine.xorshift;
    auto gen = Xorshift(1);
    auto s = gen.rand!bool;
}

private alias Iota(size_t j) = Iota!(0, j);

private template Iota(size_t i, size_t j)
{
    import std.meta;
    static assert(i <= j, "Iota: i should be less than or equal to j");
    static if (i == j)
        alias Iota = AliasSeq!();
    else
        alias Iota = AliasSeq!(i, Iota!(i + 1, j));
}

/++
Params:
    gen = saturated random number generator
Returns:
    Uniformly distributed enumeration.
+/
T rand(T, G)(ref G gen)
    if (isSaturatedRandomEngine!G && is(T == enum))
{
    static if (is(T : long))
        enum tiny = [EnumMembers!T] == [Iota!(EnumMembers!T.length)];
    else
        enum tiny = false;
    static if (tiny)
    {
        return cast(T) gen.randIndex(EnumMembers!T.length);
    }
    else
    {
        static immutable T[EnumMembers!T.length] members = [EnumMembers!T];
        return members[gen.randIndex($)];
    }
}

///
unittest
{
    import random.engine.xorshift;
    auto gen = Xorshift(1);
    enum A { a, b, c }
    auto e = gen.rand!A;
}

///
unittest
{
    import random.engine.xorshift;
    auto gen = Xorshift(1);
    enum A : dchar { a, b, c }
    auto e = gen.rand!A;
}

///
unittest
{
    import random.engine.xorshift;
    auto gen = Xorshift(1);
    enum A : string { a = "a", b = "b", c = "c" }
    auto e = gen.rand!A;
}

/++
Params:
    gen = saturated random number generator
    boundExp = bound exponent (optional).
Returns:
    Uniformly distributed real for interval `(2^^(-boundExp) , 2^^boundExp)`.

Note: `fabs` can be used to get a value from positive interval `[0, 2^^boundExp)`.
+/
T rand(T, G)(ref G gen, sizediff_t boundExp = 0)
    if (isSaturatedRandomEngine!G && isFloatingPoint!T)
{
    assert(boundExp <= T.max_exp);
    assert(boundExp >= T.min_exp - 1);
    static if (is(T == float))
    {
        auto d = gen.rand!uint;
        enum uint EXPMASK = 0x7F80_0000;
        boundExp -= T.min_exp - 1;
        uint exp = EXPMASK & d;
        exp = cast(uint) (boundExp - (exp ? bsf(exp) - (T.mant_dig - 1) : gen.randGeometric));
        if(cast(int)exp < 0)
            exp = 0;
        d = (exp << (T.mant_dig - 1)) ^ (d & ~EXPMASK);
        return *cast(T*)&d;
    }
    else
    static if (is(T == double))
    {
        auto d = gen.rand!ulong;
        enum ulong EXPMASK = 0x7FF0_0000_0000_0000;
        boundExp -= T.min_exp - 1;
        ulong exp = EXPMASK & d;
        exp = cast(ulong) (boundExp - (exp ? bsf(exp) - (T.mant_dig - 1) : gen.randGeometric));
        if(cast(int)exp < 0)
            exp = 0;
        d = (exp << (T.mant_dig - 1)) ^ (d & ~EXPMASK);
        return *cast(T*)&d;
    }
    else
    static if (T.mant_dig == 64)
    {
        auto d = gen.rand!uint;
        auto m = gen.rand!ulong;
        enum uint EXPMASK = 0x7FFF;
        boundExp -= T.min_exp - 1;
        uint exp = EXPMASK & d;
        exp = cast(uint) (boundExp - (exp ? bsf(exp) : gen.randGeometric));
        if(cast(int)exp < 0)
            exp = 0;
        if (exp)
            m |= 1UL << 63;
        else
            m &= long.max;
        d = exp ^ (d & ~EXPMASK);
        static union U
        {
            T r;
            struct
            {
                version(LittleEndian)
                {
                    ulong m;
                    ushort e;
                }
                else
                {
                    ushort e;
                    align(2)
                    ulong m;
                }
            }
        }
        U ret = void;
        ret.e = cast(ushort)d;
        ret.m = m;
        return ret.r;
    }
    /// TODO: quadruple
    else static assert(0);
}

///
unittest
{
    import std.math: fabs;
    import random.engine.xorshift;
    auto gen = Xorshift(1);
    
    auto a = gen.rand!float;
    assert(-1 < a && a < +1);
    
    auto b = gen.rand!double(4);
    assert(-16 < b && b < +16);
    
    auto c = gen.rand!double(-2);
    assert(-0.25 < c && c < +0.25);
    
    auto d = gen.rand!double.fabs;
    assert(0 <= d && d < 1);
}

/++
Params:
    gen = uniform random number generator
    m = positive module
Returns:
    Uniformly distributed integer for interval `[0 .. m)`.
+/
T randIndex(T, G)(ref G gen, T m)
    if(isSaturatedRandomEngine!G && isUnsigned!T)
{
    assert(m, "m must be positive");
    T ret = void;
    T val = void;
    do
    {
        val = gen.rand!T;
        ret = val % m;
    }
    while (val - ret > -m);
    return ret;
}

///
unittest
{
    import random.engine.xorshift;
    auto gen = Xorshift(1);
    auto s = gen.randIndex!uint(100);
    auto n = gen.randIndex!ulong(-100);
}

version (LDC)
{
    private
    pragma(inline, true)
    size_t bsf(size_t v) pure @safe nothrow @nogc
    {
        import ldc.intrinsics;
        return cast(int)llvm_cttz(v, true);
    }
}
else
{
    import core.bitop: bsf;
}

/++
    Returns: `n >= 0` such that `P(n) := 1 / (2^^(n + 1))`.
+/
size_t randGeometric(G)(ref G gen)
    if(isSaturatedRandomEngine!G)
{
    alias R = ReturnType!G;
    static if (is(R == ulong))
        alias T = size_t;
    else
        alias T = R;
    for(size_t count = 0;; count += T.sizeof * 8)
        if(auto val = gen.rand!T())
            return count + bsf(val);
}

///
unittest
{
    import random.engine.xorshift;
    auto gen = Xorshift(cast(uint)unpredictableSeed);
    auto v = gen.randGeometric();
}
