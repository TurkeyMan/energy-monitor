module urt.bigint;

import urt.math;
import urt.traits : isIntegral, isSignedIntegral, Signed;
import urt.util : clz, ctz, IsPowerOf2, NextPowerOf2;
import urt.intrinsic;

version (BigEndian)
    static assert(false, "TODO: support BigEndian!");

version = UseAlloca;

pure nothrow @nogc:


alias big_uint(uint Bits) = big_int!(Bits, false);

struct big_int(uint Bits, bool Signed = true)
{
    static assert((Bits & 63) == 0, "Size must be a multiple of 64 bits");

    alias BaseInt = ulong; // .BaseInt
    alias This = big_int!(Bits, Signed);

    enum size_t num_elements = Bits / (BaseInt.sizeof*8);
    enum This min = (){ This r; static if (Signed) { r.un.u[$-1] |= 1UL << 63; } return r; }();
    enum This max = (){ This r; r.un.u[] = ulong.max; static if (Signed) { r.un.u[$-1] >>>= 1; } return r; }();

    uint_n!(num_elements, BaseInt) un;

    this(I)(I i)
        if (isIntegral!I)
    {
        un.u[0] = i;
        static if (num_elements > 1 && isSignedIntegral!I)
            un.u[1..$] = (cast(long)un.u[0]) >> 63;
    }

    this(ulong[] i...)
    {
        assert(i.length <= num_elements, "Too many elements!");
        un.u[0..i.length] = i[];
    }

    this(uint N, bool S)(big_int!(N, S) rh)
    {
        static assert(N <= Bits, "Cannot convert to a smaller type!"); // TODO: match DMD error message...
        static if (N < Bits)
            un = ext!(S, num_elements)(rh.un);
        else
            un = rh.un;
    }

    bool opCast(T : bool)() const
    {
        foreach (i; 0 .. num_elements)
            if (un.u[i])
                return true;
        return false;
    }

    auto opUnary(string op)() const
        if (op == "-" || op == "~")
    {
        This result = void;
        foreach (i; 0 .. num_elements)
            result.un.u[i] = ~un.u[i];
        static if (op == "-")
        {
            foreach (i; 0 .. num_elements)
            {
                if (result.un.u[i] != ulong.max)
                {
                    result.un.u[i] += 1;
                    return result;
                }
                result.un.u[i] = 0;
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
            if (un.u[i] != cmp)
            {
                static if (op == "++")
                    ++un.u[i];
                else
                    --un.u[i];
                return;
            }
            un.u[i] = wrap;
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
                    result.un.u[i] = un.u[i] | rh.un.u[i];
                else static if (op == "&")
                    result.un.u[i] = un.u[i] & rh.un.u[i];
                else
                    result.un.u[i] = un.u[i] ^ rh.un.u[i];
            }
            else static if (i < num_elements)
            {
                static if (op == "|")
                    result.un.u[i] = un.u[i] | sext;
                else static if (op == "&")
                    result.un.u[i] = un.u[i] & sext;
                else
                    result.un.u[i] = un.u[i] ^ sext;
            }
            else
            {
                static if (op == "|")
                    result.un.u[i] = sext | rh.un.u[i];
                else static if (op == "&")
                    result.un.u[i] = sext & rh.un.u[i];
                else
                    result.un.u[i] = sext ^ rh.un.u[i];
            }
        }
        return result;
    }

    auto opBinary(string op)(uint shift) const
        if (op == "<<" || op == ">>" || op == ">>>")
    {
        This result = this;
        static if (op == "<<")
            shl(result, shift);
        else static if (op == ">>>" || !Signed)
            shr!false(result, shift);
        else
            shr!true(result, shift);
        return result;
    }

    auto opBinary(string op, uint N, bool S)(big_int!(N, S) rh) const
        if (op == "+" || op == "-")
    {
        alias sum = sumcarry!(op == "-", BaseInt);

        static if (N < Bits)
        {
            ref a = un;
            auto b = ext!(S, num_elements)(rh.un);
        }
        else static if (Bits < N)
        {
            auto a = ext!(Signed, rh.num_elements)(un);
            ref b = rh.un;
        }
        else
        {
            ref a = un;
            ref b = rh.un;
        }

        Result!(Bits, Signed, N, S) result = void;
        sum(a, b, result.un);
        return result;
    }

    auto opBinary(string op : "*", uint N, bool S)(ref const big_int!(N, S) rh) const
        if (Bits == N && IsPowerOf2!Bits)
    {
        static assert(Signed == false && S == false, "TODO: signed multiplication not supported yet...");
        Result!(Bits, Signed, N, S, true) res = void;
        res.un = umul(un, rh.un);
        return res;
    }

    auto opBinary(string op : "*", uint N, bool S)(ref const big_int!(N, S) rh) const
        if (Bits != N || !IsPowerOf2!Bits)
    {
        // mismatched or odd sizes will scale to the nearest power of 2 for recursive subdivision
        enum mulSize = NextPowerOf2!(Bits > N ? Bits : N);
        return big_int!(mulSize, Signed)(this) * big_int!(mulSize, S)(rh);
    }

    auto opBinary(string op : "/", uint N, bool S)(ref const big_int!(N, S) rh) const
    {
        static assert(Signed == false && S == false, "TODO: signed division not supported yet...");
        This res = void;
        big_uint!N rem = void; // TODO: version that doesn't return the remainder...
        res.un = udivrem(un, rh.un, rem.un);
        return res;
    }

    auto opBinary(string op : "%", uint N, bool S)(ref const big_int!(N, S) rh) const
    {
        static assert(Signed == false && S == false, "TODO: signed division not supported yet...");
        big_uint!N res = void; // TODO: version that doesn't return the quotient?
        udivrem(un, rh.un, res.un);
        return res;
    }

    auto divrem(uint N, bool S)(ref const big_int!(N, S) rh, out big_int!(N, S) rem) const
    {
        static assert(Signed == false && S == false, "TODO: signed division not supported yet...");
        This res = void;
        res.un = udivrem(un, rh.un, rem.un);
        return res;
    }

    auto modMul()(ref const big_uint!Bits rh, ref const big_uint!Bits mod) const
    {
        static if (Signed)
            assert(false, "TODO: signed division not supported yet...");
        else
            return (this * rh) % mod;
    }

    auto powMod(uint N)(ref const big_uint!N e, ref const big_uint!Bits mod) const
    {
        static if (Signed)
            assert(false, "TODO: signed division not supported yet...");
        else
        {
            big_uint!Bits result = 1;
            big_uint!Bits t = this % mod;
            for (int i = N-1; i >= 0; --i)
            {
                result = result.modMul(result, mod);
                if (e.bitSet(i))
                    result = result.modMul(t, mod);
            }
            return result;
        }
    }

    bool bitSet(uint bit) const
    {
        assert(bit < Bits, "Bit out of range!");
        return (un.u[bit / un.element_bits] & (1UL << (bit % un.element_bits))) != 0;
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
        un.u = r.un.u[0..num_elements];
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
            const ulong sext = (cast(long)rh.un.u[$-1]) >> 63;
        else static if (Bits < N && Signed)
            const ulong sext = (cast(long)un.u[$-1]) >> 63;
        else
            enum sext = 0;

        static foreach (i; 0 .. elements)
        {
            static if (i < num_elements && i < rh.num_elements)
            {
                if (un.u[i] != rh.un.u[i])
                    return false;
            }
            else static if (i < num_elements)
            {
                if (un.u[i] != sext)
                    return false;
            }
            else
            {
                if (rh.un.u[i] != sext)
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
                if (un.u[i] < rh.un.u[i])
                    return -1;
                else if (un.u[i] > rh.un.u[i])
                    return 1;
            }
            else static if (i < num_elements)
            {
                if (un.u[i] < sext)
                    return -1;
                else if (un.u[i] > sext)
                    return 1;
            }
            else
            {
                if (rh.un.u[i] < sext)
                    return -1;
                else if (rh.un.u[i] > sext)
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
            if (un.u[j])
                return i*64 + .clz(un.u[j]);
        }}
        return Bits;
    }

    uint ctz() const
    {
        static foreach (i; 0 .. num_elements)
        {{
            if (un.u[i])
                return i*64 + .ctz(un.u[i]);
        }}
        return Bits;
    }

    This divrem(This rh, out This rem)
    {
        assert(false, "TODO.... this is where shit gets real!");
    }

private:

    long signExt() const pure
        => (cast(long)un.u[$-1]) >> 63;

    // studying the regular integer result sign rules; this is what I found...
    alias Result(uint LB, bool LS, uint RB, bool RS, bool D = false) = big_int!((LB > RB ? LB : RB) * (1 + D), LB == RB ? LS && RS : LB > RB ? LS : RS);

    static if (Bits > 64 && IsPowerOf2!Bits)
    {
        ref inout(big_int!(Bits/2, Signed)) hi() inout
            => *cast(inout big_int!(Bits/2, Signed)*)&un.hi;
        ref inout(big_int!(Bits/2, Signed)) lo() inout
            => *cast(inout big_int!(Bits/2, Signed)*)&un.lo;
    }
}

unittest
{
    big_uint!128 a;
    assert(!a);
    assert(a == big_uint!128.min);
    a += ulong.max;
    assert(a.un.u == [ulong.max, 0]);
    a += 2;
    assert(a.un.u == [1, 1]);
    a++;
    assert(a.un.u == [2, 1]);
    a += -1;
    assert(a.un.u == [1, 1]);
    a += ulong.max;
    assert(a.un.u == [0, 2]);

    a -= 1;
    assert(a.un.u == [ulong.max, 1]);

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


    // test modMul
    a = big_uint!128(0xFFFF);
    auto mod = big_uint!128(0x1E);
    auto result = a.modMul(a, mod);
    assert(result == big_uint!128(0xF));

    a = big_uint!128(0x123456789A);
    big_uint!128 c = big_uint!128(0xFEDCBA9876);
    mod = big_uint!128(~0UL, 0xE);
    result = a.modMul(c, mod);
    assert(result == big_uint!128(0xa00ad6bb6f5b0831, 0x4));

    a = big_uint!128(7);
    c = big_uint!128(256);
    mod = big_uint!128(13);
    result = a.powMod(c, mod);
    assert(result == big_uint!128(9));
}


private:

static if (size_t.sizeof == 8)
    alias BaseInt = ulong;
else
    alias BaseInt = uint;

struct uint_n(size_t N, T = BaseInt)
{
    static assert(is(T == uint) || is(T == ulong), "Only uint or ulong!");

    enum size_t num_elements = N;
    enum size_t element_bits = T.sizeof*8;
    enum size_t element_mask = element_bits-1;
    enum size_t total_bits = N*element_bits;

    this(T v)
    {
        u[0] = v;
    }

    union {
        T[N] u;
        static if (N > 1)
        {
            struct {
                version (LittleEndian)
                {
                    uint_n!(N/2, T) lo;
                    uint_n!(N/2, T) hi;
                }
                else
                {
                    static assert(false, "TODO: other code assumes u[0] is small word!");
                    uint_n!(N/2, T) hi;
                    uint_n!(N/2, T) lo;
                }
            }
            static if (N == 2 && is(T == uint))
                ulong ul;
        }
    }
}

unittest
{
    // --- uint_n tests ---
    uint_n!2 u2;
    u2.u[0] = 1;
    u2.u[1] = 2;
    assert(u2.lo.u[0] == 1);
    assert(u2.hi.u[0] == 2);

    static if (is(typeof(u2.ul))) // Check if ulong union member exists (N=2, T=uint)
    {
        uint_n!(2, uint) u2_uint;
        u2_uint.u[0] = 0x1111_1111;
        u2_uint.u[1] = 0x2222_2222;
        assert(u2_uint.ul == 0x2222_2222_1111_1111UL);
        u2_uint.ul = 0xAAAA_AAAA_BBBB_BBBBUL;
        assert(u2_uint.u[0] == 0xBBBB_BBBB);
        assert(u2_uint.u[1] == 0xAAAA_AAAA);
    }

    uint_n!4 u4;
    u4.u[0] = 1; u4.u[1] = 2; u4.u[2] = 3; u4.u[3] = 4;
    assert(u4.lo.u[0] == 1); assert(u4.lo.u[1] == 2);
    assert(u4.hi.u[0] == 3); assert(u4.hi.u[1] == 4);
    assert(u4.lo.lo.u[0] == 1);
    assert(u4.lo.hi.u[0] == 2);
    assert(u4.hi.lo.u[0] == 3);
    assert(u4.hi.hi.u[0] == 4);
}


bool equals(size_t N, T)(ref const uint_n!(N, T) a, ref const uint_n!(N, T) b)
{
    static if (N == 1)
        return a.u[0] == b.u[0];
    else
    {
        foreach (i; 0 .. N)
            if (a.u[i] != b.u[i])
                return false;
        return true;
    }
}


int compare(size_t N, T)(ref const uint_n!(N, T) a, ref const uint_n!(N, T) b)
{
    static if (N == 1)
        return a.u[0] < b.u[0] ? -1 : a.u[0] > b.u[0] ? 1 : 0;
    else
    {
        version (BigEndian) static assert(false, "TODO");
        foreach_reverse (i; 0 .. N)
        {
            if (a.u[i] < b.u[i])
                return -1;
            if (a.u[i] > b.u[i])
                return 1;
        }
        return 0;
    }
}


uint_n!(N, T) ext(bool signExt, size_t N, size_t M, T)(ref const uint_n!(M, T) a)
{
    static assert(M < N, "Target must be larger!");

    uint_n!(N, T) r = void;
    static if (signExt)
    {
        static if (T.sizeof == 4)
            T s = cast(int)a.u[$-1] >> 31;
        else
            T s = cast(long)a.u[$-1] >> 63;
    }
    else
        enum T s = 0;
    version (LittleEndian)
    {
        r.u[0..M] = a.u;
        r.u[M..$] = s;
    }
    else
        static assert(false, "TODO: other code assumes u[0] is small word!");
    return r;
}

unittest
{
    uint_n!(1, ulong) u1_val; u1_val.u[0] = 5;
    uint_n!(1, ulong) u1_neg; u1_neg.u[0] = ulong.max; // -1

    // Zero extension
    auto u2_zero = ext!(false, 2)(u1_val);
    assert(u2_zero.u[0] == 5);
    assert(u2_zero.u[1] == 0);

    auto u4_zero = ext!(false, 4)(u1_neg);
    assert(u4_zero.u[0] == ulong.max);
    assert(u4_zero.u[1..$] == [0, 0, 0]);

    // Sign extension
    auto u2_sign_pos = ext!(true, 2)(u1_val);
    assert(u2_sign_pos.u[0] == 5);
    assert(u2_sign_pos.u[1] == 0); // Positive extends with 0

    auto u2_sign_neg = ext!(true, 2)(u1_neg);
    assert(u2_sign_neg.u[0] == ulong.max);
    assert(u2_sign_neg.u[1] == ulong.max); // Negative extends with 1s

    uint_n!(2, ulong) u2_neg; u2_neg.u[0] = 0; u2_neg.u[1] = ulong.max;
    auto u4_sign_neg = ext!(true, 4)(u2_neg);
    assert(u4_sign_neg.u[0] == 0);
    assert(u4_sign_neg.u[1] == ulong.max);
    assert(u4_sign_neg.u[2] == ulong.max);
    assert(u4_sign_neg.u[3] == ulong.max);
}


uint_n!(N, T) shl(size_t N, T)(ref const uint_n!(N, T) a, uint s)
{
    uint_n!(N, T) result = void;
    if (s >= a.element_bits)
    {
        assert(s < a.total_bits, "Shift value out of range");
        uint t = s/a.element_bits;
        result.u[0 .. t] = 0;
        result.u[t .. $] = a.u[0 .. $-t];
        s &= a.element_mask;
    }
    else
        result = a;
    if (s)
    {
        static foreach_reverse (i; 0 .. N)
        {
            result.u[i] = result.u[i] << s;
            static if (i > 0)
                result.u[i] |= result.u[i-1] >> (a.element_bits - s);
        }
    }
    return result;
}

T shlc(size_t N, T)(ref uint_n!(N, T) a, uint s, T c_in = 0)
{
    if (s == 0)
        return 0;
    assert(s < a.element_bits, "Shift value out of range");

    T result = a.u[$-1] >> (a.element_bits - s);
    static foreach_reverse (i; 0 .. N)
    {
        static if (i > 0)
            a.u[i] = (a.u[i] << s) | (a.u[i-1] >> (a.element_bits - s));
        else
            a.u[i] = (a.u[i] << s) | c_in;
    }
    return result;
}

uint_n!(N, T) shr(bool arithmetic = false, size_t N, T)(ref const uint_n!(N, T) a, uint s)
{
    uint_n!(N, T) result = void;
    if (s >= a.element_bits)
    {
        assert(s < a.total_bits, "Shift value out of range");
        uint t = s/a.element_bits;
        result.u[0 .. $-t] = a.u[t .. $];
        static if (arithmetic)
            result.u[$-t .. $] = (cast(Signed!T)a.u[$-1]) >> (a.element_bits-1);
        else
            result.u[$-t .. $] = 0;
        s &= a.element_mask;
    }
    else
        result = a;
    if (s)
    {
        static foreach (i; 0 .. N)
        {
            static if (i == N - 1 && arithmetic)
                result.u[i] = (cast(Signed!T)result.u[i]) >> s;
            else
                result.u[i] = result.u[i] >> s;
            static if (i < N - 1)
                result.u[i] |= result.u[i+1] << (a.element_bits - s);
        }
    }
    return result;
}

T shrc(bool arithmetic = false, size_t N, T)(ref uint_n!(N, T) a, uint s, T c_in = 0)
{
    if (s == 0)
        return 0;
    else if (s == a.element_bits)
    {
        T r = a.u[0];
        if (arithmetic)
            c_in = cast(Signed!T)a.u[$-1] >> (a.element_bits-1);
        static foreach (i; 0 .. N-1)
            a.u[i] = a.u[i+1];
        a.u[$-1] = c_in;
        return r;
    }
    assert(s < a.element_bits, "Shift value out of range");

    T result = a.u[0] << (a.element_bits - s);
    static foreach (i; 0 .. N)
    {
        static if (i < N - 1)
            a.u[i] = (a.u[i] >> s) | (a.u[i+1] << (a.element_bits - s));
        else
        {
            static if (arithmetic)
                a.u[i] = (cast(Signed!T)a.u[i]) >> s;
            else
                a.u[i] = (a.u[i] >> s) | c_in;
        }
    }
    return result;
}

unittest
{
    // --- Shift tests ---
    alias U128 = uint_n!(2, ulong);
    alias U256 = uint_n!(4, ulong);

    // --- shl ---
    U128 a128, r128;
    a128.u = [1, 0]; // Value 1
    r128 = shl(a128, 0); assert(equals(r128, a128));
    r128 = shl(a128, 1); assert(r128.u == [2, 0]);
    r128 = shl(a128, 63); assert(r128.u == [1UL << 63, 0]);
    r128 = shl(a128, 64); assert(r128.u == [0, 1]); // Cross word boundary
    r128 = shl(a128, 65); assert(r128.u == [0, 2]);
    r128 = shl(a128, 127); assert(r128.u == [0, 1UL << 63]);

    a128.u = [ulong.max, 0]; // Value 2^64 - 1
    r128 = shl(a128, 1); assert(r128.u == [ulong.max - 1, 1]); // Carry into next word
    r128 = shl(a128, 64); assert(r128.u == [0, ulong.max]);

    // --- shr (logical) ---
    a128.u = [0, 1]; // Value 2^64
    r128 = shr!false(a128, 0); assert(equals(r128, a128));
    r128 = shr!false(a128, 1); assert(r128.u == [1UL << 63, 0]); // Bit crosses boundary
    r128 = shr!false(a128, 63); assert(r128.u == [2, 0]);
    r128 = shr!false(a128, 64); assert(r128.u == [1, 0]);
    r128 = shr!false(a128, 65); assert(r128.u == [0, 0]);
    r128 = shr!false(a128, 127); assert(r128.u == [0, 0]);

    a128.u = [ulong.max, ulong.max]; // Value 2^128 - 1
    r128 = shr!false(a128, 1); assert(r128.u == [ulong.max, ulong.max >> 1]);
    r128 = shr!false(a128, 64); assert(r128.u == [ulong.max, 0]);

    // --- shr (arithmetic) ---
    a128.u = [0, 1UL << 63]; // Negative value (-2^127 in 128 bits)
    r128 = shr!true(a128, 0); assert(equals(r128, a128));
    r128 = shr!true(a128, 1); assert(r128.u == [0, 3UL << 62]);
    r128 = shr!true(a128, 64); assert(r128.u == [1UL << 63, ulong.max]);
    r128 = shr!true(a128, 127); assert(r128.u == [ulong.max, ulong.max]); // All 1s

    a128.u = [0, 1]; // Positive value 2^64
    r128 = shr!true(a128, 1); assert(r128.u == [1UL << 63, 0]);

    // --- shlc ---
    U128 b128;
    ulong carry_out;
    b128.u = [1, 0]; // Value 1
    carry_out = shlc(b128, 1, 0); assert(carry_out == 0 && b128.u == [2, 0]);
    b128.u = [1, 0];
    carry_out = shlc(b128, 1, 1); assert(carry_out == 0 && b128.u == [3, 0]); // Carry in LSB

    b128.u = [ulong.max, 0]; // Value 2^64 - 1
    carry_out = shlc(b128, 1, 0); assert(carry_out == 0 && b128.u == [ulong.max - 1, 1]);
    b128.u = [ulong.max, 0];
    carry_out = shlc(b128, 1, 1); assert(carry_out == 0 && b128.u == [ulong.max, 1]);

    b128.u = [0, 1UL << 63]; // Value -2^127
    carry_out = shlc(b128, 1, 0); assert(carry_out == 1 && b128.u == [0, 0]); // Shift out MSB

    // --- shrc (logical) ---
    b128.u = [1, 0]; // Value 1
    carry_out = shrc!false(b128, 1, 0); assert(carry_out == (1UL << 63) && b128.u == [0, 0]); // Shift out LSB
    b128.u = [2, 0]; // Value 2
    carry_out = shrc!false(b128, 1, 0); assert(carry_out == 0 && b128.u == [1, 0]);

    b128.u = [0, 1]; // Value 2^64
    carry_out = shrc!false(b128, 1, 0); assert(carry_out == 0 && b128.u == [1UL << 63, 0]);
    b128.u = [0, 1]; // Value 2^64
    carry_out = shrc!false(b128, 1, 1UL << 63); assert(carry_out == 0 && b128.u == [1UL << 63, 1UL << 63]); // Carry in MSB

    // --- shrc (arithmetic) ---
    b128.u = [1, 1UL << 63]; // Negative value
    carry_out = shrc!true(b128, 64); assert(carry_out == 1 && b128.u == [1UL << 63, ulong.max]); // Shift out LSB, sign extend
    b128.u = [0, 1UL << 63]; // Negative value
    carry_out = shrc!true(b128, 64); assert(carry_out == 0 && b128.u == [1UL << 63, ulong.max]); // Shift out LSB (0), sign extend

    b128.u = [1, 0]; // Positive value 1
    carry_out = shrc!true(b128, 1); assert(carry_out == (1UL << 63) && b128.u == [0, 0]); // Shift out LSB, zero extend
}


alias addcarry(T) = sumcarry!(false, T);
alias addcarry32 = sumcarry!(false, uint);
alias addcarry64 = sumcarry!(false, ulong);

alias subborrow(T) = sumcarry!(true, T);
alias subborrow32 = sumcarry!(true, uint);
alias subborrow64 = sumcarry!(true, ulong);

template sumcarry(bool subtract, T = BaseInt)
{
    bool sumcarry(size_t N)(ref const uint_n!(N, T) a, ref const uint_n!(N, T) b, ref uint_n!(N, T) r, bool c_in = 0)
    {
        // TODO: LDC unrolls up to 16, but then falls to a loop with NO UNROLLING in rthe interior
        //       GDC lever unrolls at all!
        // If we want to optimise this; we should static-foreach to force unroll for small N,
        // and then surround with an outer loop
        foreach (i; 0 .. N)
        {
            static if (subtract)
                c_in = subb(a.u[i], b.u[i], r.u[i], c_in);
            else
                c_in = addc(a.u[i], b.u[i], r.u[i], c_in);
        }
        return c_in;
    }

    bool sumcarry(size_t N)(ref const uint_n!(N, T) a, T b, ref uint_n!(N, T) r, bool c_in = 0)
    {
        foreach (i; 0 .. N)
        {
            static if (subtract)
                c_in = subb(a.u[i], b, r.u[i], c_in);
            else
                c_in = addc(a.u[i], b, r.u[i], c_in);
        }
        return c_in;
    }
}

unittest
{
    alias addcarry64 = addcarry!ulong;
    alias subborrow64 = subborrow!ulong;

    uint_n!(2, ulong) a, b, r;
    bool c;

    // addcarry: No carry in, no carry out
    a.u = [10, 20]; b.u = [5, 15];
    assert(!addcarry64(a, b, r) && r.u == [15, 35]);

    // addcarry: Carry out from low word only
    a.u = [ulong.max, 20]; b.u = [5, 15];
    assert(!addcarry64(a, b, r) && r.u == [4, 36]);

    // addcarry: Carry out from high word only (overall carry out)
    a.u = [10, ulong.max]; b.u = [5, 15];
    assert(addcarry64(a, b, r) && r.u == [15, 14]);

    // addcarry: Carry out from both words (overall carry out)
    a.u = [ulong.max, ulong.max]; b.u = [5, 15];
    assert(addcarry64(a, b, r) && r.u == [4, 15]);

    // addcarry: With carry in, no overall carry out
    a.u = [10, 20]; b.u = [5, 15];
    assert(!addcarry64(a, b, r, true) && r.u == [16, 35]);

    // addcarry: With carry in, carry out from low word
    a.u = [ulong.max, 20]; b.u = [5, 15];
    assert(!addcarry64(a, b, r, true) && r.u == [5, 36]);

    // addcarry: With carry in, overall carry out
    a.u = [ulong.max, ulong.max]; b.u = [5, 15];
    assert(addcarry64(a, b, r, true) && r.u == [5, 15]);

    // subborrow: No borrow in, no borrow out
    a.u = [15, 35]; b.u = [10, 20];
    assert(!subborrow64(a, b, r) && r.u == [5, 15]);

    // subborrow: Borrow from high word only
    a.u = [5, 35]; b.u = [10, 20];
    assert(!subborrow64(a, b, r) && r.u == [ulong.max - 4, 14]);

    // subborrow: Borrow out from high word (overall borrow out)
    a.u = [15, 15]; b.u = [10, 20];
    assert(subborrow64(a, b, r) && r.u == [5, ulong.max - 4]);

    // subborrow: Borrow from high and overall borrow out
    a.u = [5, 15]; b.u = [10, 20];
    assert(subborrow64(a, b, r) && r.u == [ulong.max - 4, ulong.max - 5]);

    // subborrow: With borrow in, no overall borrow out
    a.u = [15, 35]; b.u = [10, 20];
    assert(!subborrow64(a, b, r, true) && r.u == [4, 15]);

    // subborrow: With borrow in, borrow from high word
    a.u = [5, 35]; b.u = [10, 20];
    assert(!subborrow64(a, b, r, true) && r.u == [ulong.max - 5, 14]);

    // subborrow: With borrow in, overall borrow out
    a.u = [5, 15]; b.u = [10, 20];
    assert(subborrow64(a, b, r, true) && r.u == [ulong.max - 5, ulong.max - 5]);
}


uint_n!(N*2, T) umul(size_t N, T = BaseInt)(ref const uint_n!(N, T) a, ref const uint_n!(N, T) b)
{
    uint_n!(N*2, T) r = void;
    static if (N == 1)
    {
        static if (is(T == uint))
            r.ul = mul32to64(a.u[0], b.u[0]);
        else
            r.u = mul64to128(a.u[0], b.u[0]);
    }
    else
    {
        r.lo = umul(a.lo, b.lo);
        r.hi = umul(a.hi, b.hi);

        auto t1 = umul(a.hi, b.lo);
        auto t2 = umul(a.lo, b.hi);

        bool c1 = addcarry!T(r.lo.hi, t1.lo, r.lo.hi, false);
        c1 = addcarry!T(r.hi.lo, t1.hi, r.hi.lo, c1);
        bool c2 = addcarry!T(r.lo.hi, t2.lo, r.lo.hi, false);
        c2 = addcarry!T(r.hi.lo, t2.hi, r.hi.lo, c2);

        // TODO: for small N; possible just call ADC for each c1,c2 without the if
        if(c1 + c2)
            addcarry!T(r.hi.hi, c1 + c2, r.hi.hi, false);
    }
    return r;
}

uint_n!(N, T) umull(size_t N, T = BaseInt)(ref const uint_n!(N, T) a, ref const uint_n!(N, T) b)
{
    uint_n!(N, T) r = void;
    static if (N == 1)
        r.u[0] = a.u[0] * b.u[0];
    else
    {
        r = umul(a.lo, b.lo);
        auto t1 = umul(a.hi, b.lo);
        auto t2 = umul(a.lo, b.hi);
        bool c1 = addcarry!T(r.hi, t1.lo, r.hi, false);
        bool c2 = addcarry!T(r.hi, t2.lo, r.hi, false);
    }
    return r;
}

unittest
{
    uint_n!(1, ulong) a1, b1;
    uint_n!(2, ulong) r2;

    // N=1 (ulong * ulong -> uint_n!2) - Should match mul64to128
    a1.u = [10UL]; b1.u = [20UL];
    r2 = umul(a1, b1);
    assert(r2.u == [200UL, 0UL]);

    a1.u = [ulong.max]; b1.u = [2UL];
    r2 = umul(a1, b1);
    assert(r2.u == [ulong.max - 1, 1UL]);

    a1.u = [ulong.max]; b1.u = [ulong.max];
    r2 = umul(a1, b1);
    assert(r2.u == [1UL, ulong.max - 1UL]);


    uint_n!(2, ulong) a2, b2;
    uint_n!(4, ulong) r4;

    // N=2 (128bit * 128bit -> 256bit)
    a2.u = [0, 1]; // 2^64
    b2.u = [0, 1]; // 2^64
    r4 = umul(a2, b2); // 2^128
    assert(r4.u == [0, 0, 1, 0]);

    a2.u = [ulong.max, 0]; // 2^64 - 1
    b2.u = [2, 0];
    r4 = umul(a2, b2); // (2^64-1)*2 = 2^65 - 2
    assert(r4.u == [ulong.max - 1, 1, 0, 0]);

    a2.u = [ulong.max, ulong.max]; // 2^128 - 1
    b2.u = [ulong.max, ulong.max]; // 2^128 - 1
    r4 = umul(a2, b2); // (2^128 - 1)^2 = 2^256 - 2*2^128 + 1
    assert(r4.u == [1, 0, ulong.max - 1, ulong.max]);

    // Zero cases
    a2.u = [0, 0]; b2.u = [ulong.max, ulong.max];
    r4 = umul(a2, b2);
    assert(r4.u == [0, 0, 0, 0]);
    a2.u = [ulong.max, ulong.max]; b2.u = [0, 0];
    r4 = umul(a2, b2);
    assert(r4.u == [0, 0, 0, 0]);

    // Test with specific 128-bit values
    a2.u = [0xFEDCBA9876543210, 0x123456789ABCDEF0]; // A large 128-bit number
    b2.u = [2, 0]; // Multiply by 2
    r4 = umul(a2, b2);
    // Expected: [0xFEDCBA9876543210*2, 0x123456789ABCDEF0*2 + carry]
    // Low part: 0xFEDCBA9876543210 * 2 = 0x1_FDB97530ECA86420 -> carry = 1, low = 0xFDB97530ECA86420
    // High part: 0x123456789ABCDEF0 * 2 + 1 = 0x2468ACF13579BDE0 + 1 = 0x2468ACF13579BDE1
    assert(r4.u[0] == 0xFDB97530ECA86420UL);
    assert(r4.u[1] == 0x2468ACF13579BDE1UL);
    assert(r4.u[2] == 0);
    assert(r4.u[3] == 0);

    // TODO: test umull...
}


uint_n!(N, T) udivrem(size_t N, size_t M, T)(ref const uint_n!(N, T) a, ref const uint_n!(M, T) b, out uint_n!(M, T) rem)
{
    uint_n!(N, T) q;
    static if (N == 1 && M == 1)
    {
        assert(b.u[0] != 0, "Division by zero");
        if (a.u[0] < b.u[0])
            rem.u[0] = a.u[0];
        else
        {
            q.u[0] = a.u[0] / b.u[0];
            rem.u[0] = a.u[0] % b.u[0];
        }
    }
    else
    {
        size_t bWords = dataWords(b);
        assert(bWords > 0, "Division by zero");

        if (bWords == 1)
            return udivrem(a, b.u[0], rem.u[0]);

        size_t aWords = dataWords(a);
        if (aWords == 0)
            return q;
        if (aWords < bWords)
        {
            rem.u[0 .. aWords] = a.u[0 .. aWords];
            return q;
        }

        const(uint)[] u = cast(uint[])a.u[0..aWords];
        const(uint)[] v = cast(uint[])b.u[0..bWords];
        static if (is(T == ulong))
        {
            if (u[$-1] == 0)
                u = u[0..$-1];
            if (v[$-1] == 0)
                v = v[0..$-1];
        }
        divmnu(cast(uint[])q.u[], cast(uint[])rem.u[], u, v);
    }
    return q;
}

uint_n!(N, T) udivrem(size_t N, T)(ref const uint_n!(N, T) a, T b, out T rem)
{
    assert(b != 0, "Division by zero");

    static if (N == 1)
    {
        uint_n!(N, T) q;
        if (a.u[0] < b)
            rem = a.u[0];
        else
        {
            q.u[0] = a.u[0] / b;
            rem = a.u[0] % b;
        }
        return q;
    }
    else
    {
        size_t aWords = dataWords(a);
        if (aWords == 0)
            return uint_n!(N, T)();
        if (aWords == 1)
        {
            uint_n!(N, T) q;
            if (a.u[0] < b)
                rem = a.u[0];
            else
            {
                q.u[0] = a.u[0] / b;
                rem = a.u[0] % b;
            }
            return q;
        }
        if (aWords == 2 && a.u[1] < b)
            return uint_n!(N, T)(divrem2x1(a.u[0..2], b, rem));

        // HACK: we'll use the N/N version for now until we can debug an N/1 version...
        const(uint)[] u = cast(uint[])a.u[0..aWords];
        const(uint)[] v = cast(uint[])((&b)[0..1]);
        static if (is(T == ulong))
        {
            if (u[$-1] == 0)
                u = u[0..$-1];
            if (v[$-1] == 0)
                v = v[0..$-1];
        }
        uint_n!(N, T) q;
        divmnu(cast(uint[])q.u[], cast(uint[])((&rem)[0..1]), u, v);
        return q;
/+
        // TODO: !!! THIS APPARENELY OPTOMISED VERSION DOESN'T WORK !!!

        uint_n!(N, T) quotient;
        T current_rem;

        // Iterate from the most significant word of 'a' down
        for (size_t i = N; i-- > 0; ) // Efficient loop for N-1 down to 0
        {
            // Combine the remainder from the previous step (current_rem, as the high word)
            // with the current word from the dividend (a.u[i], as the low word)
            // to form a 2-word number conceptually: (current_rem : a.u[i]).
            // Then divide this 2-word number by the single-word divisor d0.

            T next_rem;
            T[2] arg = [ current_rem, a.u[i] ];
            T q = divrem2x1(arg, b, next_rem);

            // The quotient word from this step belongs at index 'i' in the result.
            quotient.u[i] = q;

            // The remainder from this step becomes the high word for the next iteration.
            current_rem = next_rem;
        }

        // After the loop finishes, the final value in current_rem is the
        // overall remainder of the division a / b.
        rem = current_rem;

        return quotient;
+/
    }
}


unittest
{
    import core.exception : AssertError;

    // Helper to verify a = b * q + rem and rem < b
    void verify(size_t N, T)(ref const uint_n!(N, T) a, ref const uint_n!(N, T) b,
                             ref const uint_n!(N, T) q, ref const uint_n!(N, T) rem)
    {
        // Compute b * q
        uint_n!(N*2, T) sum = umul(b, q);
        // Add rem
        addcarry!T(sum, rem.ext!(false, N*2), sum);
        // Compare with a (extend a to 2*N)
        assert(compare(a.ext!(false, N*2), sum) == 0, "a != b * q + rem");
        // Check rem < b
        assert(compare(rem, b) < 0, "rem >= b");
    }

    // Test for T == uint, N == 1
    {
        uint_n!(1, uint) a, b, q, rem;

        // Simple division: 100 / 3
        a.u[0] = 100;
        b.u[0] = 3;
        q = udivrem(a, b, rem);
        assert(q.u[0] == 33, "q wrong");
        assert(rem.u[0] == 1, "rem wrong");
        verify(a, b, q, rem);

        // a < b: 5 / 10
        a.u[0] = 5;
        b.u[0] = 10;
        q = udivrem(a, b, rem);
        assert(q.u[0] == 0, "q wrong");
        assert(rem.u[0] == 5, "rem wrong");
        verify(a, b, q, rem);

        // a = 0
        a.u[0] = 0;
        b.u[0] = 7;
        q = udivrem(a, b, rem);
        assert(q.u[0] == 0, "q wrong");
        assert(rem.u[0] == 0, "rem wrong");
        verify(a, b, q, rem);

        // Division by zero
        a.u[0] = 42;
        b.u[0] = 0;
//        try // TODO...
//        {
//            q = udivrem(a, b, rem);
//            assert(false, "Expected division by zero");
//        }
    }

    // Test for T == uint, N == 2
    {
        uint_n!(2, uint) a, b, q, rem;

        // Large division: (2^32 - 1) / 3
        a.u = [0xFFFFFFFF, 0];
        b.u = [3, 0];
        q = udivrem(a, b, rem);
        assert(q.u[] == [0x55555555, 0], "q wrong");
        assert(rem.u[] == [0, 0], "rem wrong");
        verify(a, b, q, rem);

        // a < b
        a.u = [100, 0];
        b.u = [200, 0];
        q = udivrem(a, b, rem);
        assert(q.u[] == [0, 0], "q wrong");
        assert(rem.u[] == [100, 0], "rem wrong");
        verify(a, b, q, rem);

        // b with leading zeros
        a.u = [0xFFFF, 0xFFFF];
        b.u = [0xFF, 0];
        q = udivrem(a, b, rem);
        verify(a, b, q, rem);
    }

    // Test for T == ulong, N == 1
    {
        uint_n!(1, ulong) a, b, q, rem;

        // Simple division: 1000 / 7
        a.u[0] = 1000;
        b.u[0] = 7;
        q = udivrem(a, b, rem);
        assert(q.u[0] == 142, "q wrong");
        assert(rem.u[0] == 6, "rem wrong");
        verify(a, b, q, rem);

        // Large values: (2^64 - 1) / 2
        a.u[0] = ulong.max;
        b.u[0] = 2;
        q = udivrem(a, b, rem);
        assert(q.u[0] == (ulong.max / 2), "q wrong");
        assert(rem.u[0] == 1, "rem wrong");
        verify(a, b, q, rem);
    }

    // Test for T == ulong, N == 4
    {
        uint_n!(4, ulong) a, b, q, rem;

        // Large division: (2^128 - 1) / 3
        a.u = [ulong.max, ulong.max, 0, 0];
        b.u = [3, 0, 0, 0];
        q = udivrem(a, b, rem);
        verify(a, b, q, rem);

        // Complex case: large a, b with mixed units
        a.u = [0x1234567890ABCDEF, 0xFEDCBA0987654321, 0, 0];
        b.u = [0xFF, 0xFF, 0, 0];
        q = udivrem(a, b, rem);
        verify(a, b, q, rem);
    }
}


private:

size_t dataWords(size_t N, T)(ref const uint_n!(N, T) a)
{
    foreach_reverse (i; 0 .. N)
        if (a.u[i] != 0)
            return i + 1;
    return 0;
}


// THIS IS A 32BIT IMPLEMENTATION OF KNUTH'S ALGORITHM D
// MAYBE A 64BIT VERSION WOULD BE NICE TO HAVE?
// BIT ALSO; THIS DEPENDS ON 64->32BIT NARROWING DIV

/* q[0], r[0], u[0], and v[0] contain the LEAST significant words.
(The sequence is in little-endian order).

This is a fairly precise implementation of Knuth's Algorithm D, for a
binary computer with base b = 2^^32. The caller supplies:
1. Space q for the quotient, m - n + 1 words (at least one).
2. Space r for the remainder, n words.
3. The dividend u, m words, m >= 1.
4. The divisor v, n words, n >= 2.
The most significant digit of the divisor, v[n-1], must be nonzero.  The
dividend u may have leading zeros; this just makes the algorithm take
longer and makes the quotient contain more leading zeros.
The program does not alter the input parameters u and v.
The quotient and remainder returned may have leading zeros.  The
function itself returns a value of 0 for success and 1 for invalid
parameters (e.g., division by 0).
For now, we must have m >= n.  Knuth's Algorithm D also requires
that the dividend be at least as long as the divisor.  (In his terms,
m >= 0 (unstated).  Therefore m+n >= n.) */
void divmnu(uint[] q, uint[] r, const uint[] u, const uint[] v)
{
    enum b = 1UL<<32; // Number base (2^^32).
    const size_t m = u.length;
    const size_t n = v.length;

    debug assert(m >= n && n > 0 && v[n-1] != 0, "Invalid parameters");

    long t, k;
    ptrdiff_t s, i, j;

    if (n == 1)
    {                                   // Take care of
        k = 0;                          // the case of a
        for (j = m - 1; j >= 0; j--)    // single-digit
        {                               // divisor here.
            q[j] = cast(uint)((k*b + u[j])/v[0]);
            k = (k*b + u[j]) - q[j]*v[0];
        }
        r[0] = cast(uint)k;
        return;
    }

    version (UseAlloca)
    {
        // alloca is not strictly pure, but we can use it here while maintaining purity
        pragma(mangle, "alloca") extern(C) void* allocaPureHack(size_t size) pure nothrow @nogc;
        uint* tmp = cast(uint*)allocaPureHack((n + m + 1)*4);
    }
    else
    {
        uint[257] temp = void; // space for n <= 128, m <= 128
        assert(n + m + 1 <= temp.length, "Not enough space in temp array");
        uint* tmp = temp.ptr;
    }
    uint* vn = tmp;     // Normalized form of v.
    uint* un = vn + n;  // Normalized form of u.
    ulong qhat;         // Estimated quotient digit.
    ulong rhat;         // A remainder.
    ulong p;            // Product of two digits.

    /* Normalize by shifting v left just enough so that its high-order
    bit is on, and shift u left the same amount. We may have to append a
    high-order digit on the dividend; we do that unconditionally. */

    s = clz(v[n-1]);             // 0 <= s <= 31.
    for (i = n - 1; i > 0; i--)
        vn[i] = (v[i] << s) | (cast(ulong)v[i-1] >> (32-s));
    vn[0] = v[0] << s;

    un[m] = cast(ulong)u[m-1] >> (32-s);
    for (i = m - 1; i > 0; i--)
        un[i] = (u[i] << s) | (cast(ulong)u[i-1] >> (32-s));
    un[0] = u[0] << s;

    for (j = m - n; j >= 0; j--)
    {
        // Compute estimate qhat of q[j].
        qhat = (un[j+n]*b + un[j+n-1])/vn[n-1];
        rhat = (un[j+n]*b + un[j+n-1]) - qhat*vn[n-1];
    again:
        if (qhat >= b || qhat*vn[n-2] > b*rhat + un[j+n-2])
        {
            qhat = qhat - 1;
            rhat = rhat + vn[n-1];
            if (rhat < b)
                goto again;
        }

        // Multiply and subtract.
        k = 0;
        for (i = 0; i < n; i++)
        {
            p = qhat*vn[i];
            t = un[i+j] - k - (p & 0xFFFFFFFFUL);
            un[i+j] = cast(uint)t;
            k = (p >> 32) - (t >> 32);
        }
        t = un[j+n] - k;
        debug assert(ulong(t) <= uint.max); // the reference implementation has all these casts
        un[j+n] = cast(uint)t;

        debug assert(ulong(qhat) <= uint.max); // the reference implementation has all these casts
        q[j] = cast(uint)qhat;  // Store quotient digit.
        if (t < 0)              // If we subtracted too
        {                       // much, add back.
            q[j] = q[j] - 1;
            k = 0;
            for (i = 0; i < n; i++)
            {
                t = cast(ulong)un[i+j] + vn[i] + k;
                un[i+j] = cast(uint)t;
                k = t >> 32;
            }
            auto tt = un[j+n] + k;
            debug assert(ulong(tt) <= uint.max); // the reference implementation has all these casts
            un[j+n] = cast(uint)tt;
        }
    }
    // If the caller wants the remainder, unnormalize it and pass it back.
    for (i = 0; i < n-1; i++)
    {
        auto tt = (un[i] >> s) | (cast(ulong)un[i+1] << (32-s));
        r[i] = cast(uint)tt;
    }
    r[n-1] = un[n-1] >> s;
}
