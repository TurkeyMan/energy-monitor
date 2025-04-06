module urt.bigint;

import urt.traits : isIntegral, isSignedIntegral;
import urt.util : clz, ctz, IsPowerOf2, NextPowerOf2;
import urt.intrinsic;

version (X86) version = Intel;
version (X86_64) version = Intel;
version (Intel) version (LDC) version = Intel_LDC;

version (BigEndian)
    static assert(false, "TODO: support BigEndian!");

pure nothrow @nogc:


alias big_uint(uint Bits) = big_int!(Bits, false);

struct big_int(uint Bits, bool Signed = true)
{
    static assert((Bits & 63) == 0, "Size must be a multiple of 64 bits");

    alias This = big_int!(Bits, Signed);

    enum size_t num_elements = Bits / 64;
    enum This min = (){ This r; static if (Signed) { r.ul[$-1] |= 1UL << 63; } return r; }();
    enum This max = (){ This r; r.ul[] = ulong.max; static if (Signed) { r.ul[$-1] >>>= 1; } return r; }();

    ulong[num_elements] ul;

    this(I)(I i)
        if (isIntegral!I)
    {
        ul[0] = i;
        static if (num_elements > 1 && isSignedIntegral!I)
            ul[1..$] = (cast(long)ul[0]) >> 63;
    }

    this(uint N, bool S)(big_int!(N, S) rh)
    {
        static assert(N <= Bits, "Cannot convert to a smaller type!"); // TODO: match DMD error message...
        ul[0..rh.num_elements] = rh.ul;
        static if (N < Bits && S)
            ul[rh.num_elements..$] = rh.signExt;
    }

    bool opCast(T : bool)() const
    {
        foreach (i; 0 .. num_elements)
            if (ul[i])
                return true;
        return false;
    }

    auto opUnary(string op)() const
        if (op == "-" || op == "~")
    {
        This result = void;
        foreach (i; 0 .. num_elements)
            result.ul[i] = ~ul[i];
        static if (op == "-")
        {
            foreach (i; 0 .. num_elements)
            {
                if (result.ul[i] != ulong.max)
                {
                    result.ul[i] += 1;
                    return result;
                }
                result.ul[i] = 0;
            }
        }
        return result;
    }

    void opUnary(string op)()
        if (op == "++" || op == "--")
    {
        enum cmp = op == "++" ? ulong.max : 0;
        enum wrap = op == "++" ? 0 : ulong.max;

        foreach (i; 0 .. num_elements)
        {
            if (ul[i] != cmp)
            {
                static if (op == "++")
                    ++ul[i];
                else
                    --ul[i];
                return;
            }
            ul[i] = wrap;
        }
    }

    auto opBinary(string op, uint N, bool S)(big_int!(N, S) rh) const
        if (op == "|" || op == "&" || op == "^")
    {
        Result!(Bits, Signed, N, S) result = void;

        static if (N < Bits && S)
            const ulong sext = (cast(long)rh.ul[$-1]) >> 63;
        else static if (Bits < N && Signed)
            const ulong sext = (cast(long)ul[$-1]) >> 63;
        else
            enum sext = 0;

        static foreach (i; 0 .. result.num_elements)
        {
            static if (i < num_elements && i < rh.num_elements)
            {
                static if (op == "|")
                    result.ul[i] = ul[i] | rh.ul[i];
                else static if (op == "&")
                    result.ul[i] = ul[i] & rh.ul[i];
                else
                    result.ul[i] = ul[i] ^ rh.ul[i];
            }
            else static if (i < num_elements)
            {
                static if (op == "|")
                    result.ul[i] = ul[i] | sext;
                else static if (op == "&")
                    result.ul[i] = ul[i] & sext;
                else
                    result.ul[i] = ul[i] ^ sext;
            }
            else
            {
                static if (op == "|")
                    result.ul[i] = sext | rh.ul[i];
                else static if (op == "&")
                    result.ul[i] = sext & rh.ul[i];
                else
                    result.ul[i] = sext ^ rh.ul[i];
            }
        }
        return result;
    }

    auto opBinary(string op)(uint shift) const
        if (op == "<<" || op == ">>" || op == ">>>")
    {
        This result = void;

        if (shift >= 64)
        {
            assert(shift < Bits, "Shift value out of range");

            uint s = shift >> 6;
            static if (op == "<<")
            {
                result.ul[0 .. s] = 0;
                result.ul[s .. $] = ul[0 .. $-s];
            }
            else
            {
                result.ul[0 .. $-s] = ul[s .. $];
                static if (op == ">>" && Signed)
                    result.ul[$-s .. $] = (cast(long)ul[$-1]) >> 63;
                else
                    result.ul[$-s .. $] = 0;
            }
            shift &= 63;
        }
        else
            result.ul = ul;

        if (shift & 63)
        {
            static if (op == "<<")
            {
                static foreach_reverse (i; 0 .. num_elements)
                {
                    result.ul[i] = result.ul[i] << shift;
                    static if (i > 0)
                        result.ul[i] |= result.ul[i-1] >> (64 - shift);
                }
            }
            else
            {
                static foreach (i; 0 .. num_elements)
                {
                    static if (i == num_elements - 1 && op == ">>" && Signed)
                        result.ul[i] = (cast(long)result.ul[i]) >> shift;
                    else
                        result.ul[i] = result.ul[i] >> shift;
                    static if (i < num_elements - 1)
                        result.ul[i] |= result.ul[i+1] << (64 - shift);
                }
            }
        }

        return result;
    }

    auto opBinary(string op, uint N, bool S)(big_int!(N, S) rh) const
        if (op == "+" || op == "-")
    {
        alias sum = sumcarry!(op == "-", ulong);

        Result!(Bits, Signed, N, S) result = void;
        enum elements = result.num_elements;

        enum less_elements = num_elements < rh.num_elements ? num_elements : rh.num_elements;

        bool c = sum!less_elements(ul[0..less_elements], rh.ul[0..less_elements], result.ul[0..less_elements]);
        static if (less_elements < elements)
        {
            enum tail = elements - less_elements;

            static if (N < Bits && S)
                const ulong sext = (cast(long)rh.ul[$-1]) >> 63;
            else static if (Bits < N && Signed)
                const ulong sext = (cast(long)ul[$-1]) >> 63;
            else
                enum sext = 0;

            static if (num_elements < rh.num_elements)
                sum!tail(rh.ul[less_elements..$][0..tail], sext, result.ul[less_elements..$][0..tail], c);
            else
                sum!tail(ul[less_elements..$][0..tail], sext, result.ul[less_elements..$][0..tail], c);
        }

        return result;
    }

    auto opBinary(string op : "*", uint N, bool S)(big_int!(N, S) rh) const
        if (Bits == 64 && N == 64)
    {
        static assert(Signed == false && S == false, "TODO: signed multiplication not supported yet...");

        ulong al = cast(uint)ul[0];
        ulong bl = cast(uint)rh.ul[0];
        ulong t = (al * bl);
        ulong w3 = cast(uint)t;
        ulong k = (t >> 32);

        ulong ah = ul[0] >> 32;
        t = (ah * bl) + k;
        k = cast(uint)t;
        ulong w1 = (t >> 32);

        ulong bh = rh.ul[0] >> 32;
        t = (al * bh) + k;
        k = (t >> 32);

        Result!(Bits, Signed, N, S, true) result = void;
        result.ul[0] = (t << 32) + w3;
        result.ul[1] = (ah * bh) + w1 + k;
        return result;
    }

    auto opBinary(string op : "*", uint N, bool S)(big_int!(N, S) rh) const
        if (Bits == N && Bits > 64 && IsPowerOf2!Bits)
    {
        alias L = this;
        alias R = rh;
        Result!(Bits, Signed, N, S, true) Res = void;

        Res.hi = L.hi * R.hi;
        Res.lo = L.lo * R.lo;

        This T = L.hi * R.lo;
        Res.lo.hi += T.lo;
        if(Res.lo.hi < T.lo)  // if Res.lo.hi overflowed
            ++Res.hi;
        Res.hi.lo += T.hi;
        if(Res.hi.lo < T.hi)  // if Res.hi.lo overflowed
            ++Res.hi.hi;

        T = L.lo * R.hi;
        Res.lo.hi += T.lo;
        if(Res.lo.hi < T.lo)  // if Res.lo.hi overflowed
            ++Res.hi;
        Res.hi.lo += T.hi;
        if(Res.hi.lo < T.hi)  // if Res.hi.lo overflowed
            ++Res.hi.hi;

        return Res;
    }

    auto opBinary(string op : "*", uint N, bool S)(big_int!(N, S) rh) const
        if (Bits != N || !IsPowerOf2!Bits)
    {
        // mismatched or odd sizes will scale to the nearest power of 2 for recursive subdivision
        enum mulSize = NextPowerOf2!(Bits > N ? Bits : N);
        return big_int!(mulSize, Signed)(this) * big_int!(mulSize, S)(rh);
    }

    auto opBinary(string op, I)(I rh) const
        if (isIntegral!I)
    {
        static if (isSignedIntegral!I)
            return this.opBinary!op(big_int!64(rh));
        else
            return this.opBinary!op(big_uint!64(rh));
    }
    auto opBinaryRight(string op, I)(I rh) const
        if (isIntegral!I)
    {
        static if (isSignedIntegral!I)
            return big_int!64(rh).opBinary!op(this);
        else
            return big_uint!64(rh).opBinary!op(this);
    }

    void opOpAssign(string op, uint N, bool S)(big_int!(N, S) rh)
    {
        auto r = this.opBinary!op(rh);
        assert(num_elements <= r.num_elements);
        ul = r.ul[0..num_elements];
    }

    void opOpAssign(string op, I)(I rh)
        if (isIntegral!I)
    {
        static if (isSignedIntegral!I)
            this.opOpAssign!op(big_int!64(rh));
        else
            this.opOpAssign!op(big_uint!64(rh));
    }

    bool opEquals(uint N, bool S)(big_int!(N, S) rh) const
    {
        enum elements = num_elements > rh.num_elements ? num_elements : rh.num_elements;

        static if (N < Bits && S)
            const ulong sext = (cast(long)rh.ul[$-1]) >> 63;
        else static if (Bits < N && Signed)
            const ulong sext = (cast(long)ul[$-1]) >> 63;
        else
            enum sext = 0;

        static foreach (i; 0 .. elements)
        {
            static if (i < num_elements && i < rh.num_elements)
            {
                if (ul[i] != rh.ul[i])
                    return false;
            }
            else static if (i < num_elements)
            {
                if (ul[i] != sext)
                    return false;
            }
            else
            {
                if (rh.ul[i] != sext)
                    return false;
            }
        }
        return true;
    }

    bool opEquals(I)(I rh) const
        if (isIntegral!I)
    {
        static if (isSignedIntegral!I)
            return this == big_int!64(rh);
        else
            return this == big_uint!64(rh);
    }

    int opCmp(uint N, bool S)(big_int!(N, S) rh) const
    {
        enum elements = num_elements > rh.num_elements ? num_elements : rh.num_elements;

        static if (N < Bits && S)
            const ulong sext = (cast(long)rh.ul[$-1]) >> 63;
        else static if (Bits < N && Signed)
            const ulong sext = (cast(long)ul[$-1]) >> 63;
        else
            enum sext = 0;

        static foreach_reverse (i; 0 .. elements)
        {
            static if (i < num_elements && i < rh.num_elements)
            {
                if (ul[i] < rh.ul[i])
                    return -1;
                else if (ul[i] > rh.ul[i])
                    return 1;
            }
            else static if (i < num_elements)
            {
                if (ul[i] < sext)
                    return -1;
                else if (ul[i] > sext)
                    return 1;
            }
            else
            {
                if (rh.ul[i] < sext)
                    return -1;
                else if (rh.ul[i] > sext)
                    return 1;
            }
        }
        return 0;
    }

    int opCmp(I)(I rh) const
        if (isIntegral!I)
    {
        static if (isSignedIntegral!I)
            return this.opCmp(big_int!64(rh));
        else
            return this.opCmp(big_uint!64(rh));
    }

    uint clz() const
    {
        static foreach (i; 0 .. num_elements)
        {{
            enum j = num_elements - i - 1;
            if (ul[j])
                return i*64 + .clz(ul[j]);
        }}
        return Bits;
    }

    uint ctz() const
    {
        static foreach (i; 0 .. num_elements)
        {{
            if (ul[i])
                return i*64 + .ctz(ul[i]);
        }}
        return Bits;
    }

    This divrem(This rh, out This rem)
    {
        assert(false, "TODO.... this is where shit gets real!");
    }

private:

    long signExt() const pure
        => (cast(long)ul[$-1]) >> 63;

    // studying the regular integer result sign rules; this is what I found...
    alias Result(uint LB, bool LS, uint RB, bool RS, bool D = false) = big_int!((LB > RB ? LB : RB) * (1 + D), LB == RB ? LS && RS : LB > RB ? LS : RS);

    static if (Bits > 64 && IsPowerOf2!Bits)
    {
        ref inout(big_int!(Bits/2, Signed)) hi() inout
            => *cast(inout big_int!(Bits/2, Signed)*)&ul[$/2];
        ref inout(big_int!(Bits/2, Signed)) lo() inout
            => *cast(inout big_int!(Bits/2, Signed)*)&this;
    }
}


private:


unittest
{
    big_uint!128 a;
    assert(!a);
    assert(a == big_uint!128.min);
    a += ulong.max;
    assert(a.ul == [ulong.max, 0]);
    a += 2;
    assert(a.ul == [1, 1]);
    a++;
    assert(a.ul == [2, 1]);
    a += -1;
    assert(a.ul == [1, 1]);
    a += ulong.max;
    assert(a.ul == [0, 2]);

    a -= 1;
    assert(a.ul == [ulong.max, 1]);

    a = big_uint!128(0);
    a -= 1;
    assert(a == big_uint!128.max);
    ++a;
    assert(a == big_uint!128(0));
    a = -a;
    assert(a == big_uint!128(0));

    big_int!128 b;
    assert(b != big_int!128.min);
    assert(b != big_int!128.max);
    b = big_int!128.min;
    b = -b;
    assert(b == big_int!128.min);

    --b;
    assert(b == big_int!128.max);
    b = ~b;
    assert(b == big_int!128.min);

    assert((big_int!128.min | big_int!128.max) == big_uint!128.max);
    assert((big_int!128.min & big_int!128.max) == big_uint!128.min);
    assert((big_int!128.min ^ big_int!128.max) == big_uint!128.max);
    assert((big_int!128.min ^ big_uint!128.max) == big_int!128.max);

    auto r = big_uint!128.max * big_uint!128.max;
    big_uint!256 m2 = big_uint!128.max*2U;
    assert(r == big_uint!256.max - m2);
}



/+
void f(I, J)(I i = I(), J j = J())
{
    pragma(msg, I, " | ", J, ": ", typeof(i | j));
}
void tt()
{
    f!(int, int)(0,0);
    f!(int, uint)(0,0);
    f!(uint, int)(0,0);
    f!(uint, uint)(0,0);

    f!(long, long)(0,0);
    f!(long, ulong)(0,0);
    f!(ulong, long)(0,0);
    f!(ulong, ulong)(0,0);

    f!(int, long)(0,0);
    f!(int, ulong)(0,0);
    f!(uint, long)(0,0);
    f!(uint, ulong)(0,0);
    f!(long, int)(0,0);
    f!(long, uint)(0,0);
    f!(ulong, int)(0,0);
    f!(ulong, uint)(0,0);

    f!(int, byte)(0,0);
    f!(int, ubyte)(0,0);
    f!(uint, byte)(0,0);
    f!(uint, ubyte)(0,0);
    f!(byte, int)(0,0);
    f!(byte, uint)(0,0);
    f!(ubyte, int)(0,0);
    f!(ubyte, uint)(0,0);

    f!(byte, long)(0,0);
    f!(byte, ulong)(0,0);
    f!(ubyte, long)(0,0);
    f!(ubyte, ulong)(0,0);
    f!(long, byte)(0,0);
    f!(long, ubyte)(0,0);
    f!(ulong, byte)(0,0);
    f!(ulong, ubyte)(0,0);
/+
    f!(big_int!128, big_int!128)();
    f!(big_int!128, big_uint!128)();
    f!(big_uint!128, big_int!128)();
    f!(big_uint!128, big_uint!128)();

    f!(big_int!64, big_int!128)();
    f!(big_int!64, big_uint!128)();
    f!(big_uint!64, big_int!128)();
    f!(big_uint!64, big_uint!128)();
    f!(big_int!128, big_int!64)();
    f!(big_int!128, big_uint!64)();
    f!(big_uint!128, big_int!64)();
    f!(big_uint!128, big_uint!64)();

    f!(byte, big_int!128)();
    f!(byte, big_uint!128)();
    f!(ubyte, big_int!128)();
    f!(ubyte, big_uint!128)();
    f!(big_int!128, byte)();
    f!(big_int!128, ubyte)();
    f!(big_uint!128, byte)();
    f!(big_uint!128, ubyte)();
+/
}
+/


alias addcarry32 = sumcarry!(false, uint);
alias addcarry64 = sumcarry!(false, ulong);

alias subborrow32 = sumcarry!(true, uint);
alias subborrow64 = sumcarry!(true, ulong);

template sumcarry(bool subtract, T = uint)
    if (is(T == uint) || is(T == ulong))
{
    bool sumcarry(size_t N)(ref const T[N] a, ref const T[N] b, ref T[N] r, bool c_in = 0)
    {
        static if (is(T == uint) && N > 8)
        {
            // let's do really big ones in 256-bit blocks...
            size_t i = 0;
            for (; i + 8 <= N; i += 8)
                c_in = sumcarry!8((&a[i])[0..8], (&b[i])[0..8], (&r[i])[0..8], c_in);
            enum Tail = N & 7;
            static if (Tail)
                c_in = sumcarry!Tail((&a[i])[0..Tail], (&b[i])[0..Tail], (&r[i])[0..Tail], c_in);
            return c_in;
        }
        else static if (is(T == ulong) && size_t.sizeof < 8)
        {
            // 32-bit pass-throuugh
            auto thunk = cast(bool function(ref const ulong[N], ref const ulong[N], ref ulong[N], bool) nothrow @nogc pure @safe)&sumcarry!(N*2);
            return thunk(a, b, r, c_in);
        }
        else
        {
            version (Intel_LDC)
                alias CT = ubyte;
            else
                alias CT = T;
            CT c = c_in;
            foreach (i; 0 .. N)
            {
                version (LDC)
                {
                    version (Intel)
                    {
                        static if (subtract)
                            auto cr = _x86_subborrow(c, a[i], b[i]);
                        else
                            auto cr = _x86_addcarry(c, a[i], b[i]);
                        r[i] = cr.r;
                        c = cr.c;
                    }
                    else
                    {
                        static if (subtract)
                        {
                            auto r1 = _llvm_sub_overflow(a[i], b[i]);
                            auto r2 = _llvm_sub_overflow(r1.r, c);
                        }
                        else
                        {
                            auto r1 = _llvm_add_overflow(a[i], b[i]);
                            auto r2 = _llvm_add_overflow(r1.r, c);
                        }
                        r[i] = r2.r;
                        c = r1.c | r2.c;
                    }
                }
                else version (GNU)
                {
                    static if (subtract)
                        r[i] = __builtin_subc(a[i], b[i], c, &c);
                    else
                        r[i] = __builtin_addc(a[i], b[i], c, &c);
                }
                else
                {
                    static if (subtract)
                    {
                        T t = b[i] + c;
                        r[i] = a[i] - t;
                        c = (t < c) + (r[i] > t);
                    }
                    else
                    {
                        T t = b[i] + c;
                        r[i] = a[i] + t;
                        c = (t < c) + (r[i] < t);
                    }
                }
            }
            return c != 0;
        }
    }

    bool sumcarry(size_t N)(ref const T[N] a, T b, ref T[N] r, bool c_in = 0)
    {
        static if (is(T == uint) && N > 8)
        {
            // let's do really big ones in 256-bit blocks...
            size_t i = 0;
            for (; i + 8 <= N; i += 8)
                c_in = sumcarry!8((&a[i])[0..8], b, (&r[i])[0..8], c_in);
            enum Tail = N & 7;
            static if (Tail)
                c_in = sumcarry!Tail((&a[i])[0..Tail], b, (&r[i])[0..Tail], c_in);
            return c_in;
        }
        else static if (is(T == ulong) && size_t.sizeof < 8)
        {
            // 32-bit pass-throuugh
            debug assert(b == 0 || ~b == 0, "Only works for sign-extend operations!");
            return sumcarry!(subtract, uint).sumcarry!(N*2)(*cast(uint[N*2]*)&a, cast(uint)b, *cast(uint[N*2]*)&r, c_in);
        }
        else
        {
            version (Intel_LDC)
                alias CT = ubyte;
            else
                alias CT = T;
            CT c = c_in;
            foreach (i; 0 .. N)
            {
                version (LDC)
                {
                    version (Intel)
                    {
                        static if (subtract)
                            auto cr = _x86_subborrow(c, a[i], b);
                        else
                            auto cr = _x86_addcarry(c, a[i], b);
                        r[i] = cr.r;
                        c = cr.c;
                    }
                    else
                    {
                        static if (subtract)
                        {
                            auto r1 = _llvm_sub_overflow(a[i], b);
                            auto r2 = _llvm_sub_overflow(r1.r, c);
                        }
                        else
                        {
                            auto r1 = _llvm_add_overflow(a[i], b);
                            auto r2 = _llvm_add_overflow(r1.r, c);
                        }
                        r[i] = r2.r;
                        c = r1.c | r2.c;
                    }
                }
                else version (GNU)
                {
                    static if (subtract)
                        r[i] = __builtin_subc(a[i], b, c, &c);
                    else
                        r[i] = __builtin_addc(a[i], b, c, &c);
                }
                else
                {
                    static if (subtract)
                    {
                        T t = b + c;
                        r[i] = a[i] - t;
                        c = (t < c) + (r[i] > t);
                    }
                    else
                    {
                        T t = b + c;
                        r[i] = a[i] + t;
                        c = (t < c) + (r[i] < t);
                    }
                }
            }
            return c != 0;
        }
    }
}

pragma(inline, true)
ulong mul32to64(uint a, uint b)
{
    return cast(ulong)a * b;
}

pragma(inline, true)
long mul32to64(int a, int b)
{
    return cast(long)a * b;
}

pragma(inline, true)
long mul32to64(uint a, int b)
{
    return cast(long)a * b;
}

pragma(inline, true)
long mul32to64(int a, uint b)
{
    return a * cast(long)b;
}

/+
ulong mulu32xu32(ulong a, ulong b)
{
}

long muls32xs32(long a, long b)
{
}

long muls32xs32(ulong a, long b)
{
}

long muls32xs32(long a, ulong b)
{
}
+/
