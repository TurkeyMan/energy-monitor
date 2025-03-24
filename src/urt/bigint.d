module urt.bigint;

import urt.traits : isIntegral, isSignedIntegral;
import urt.util : clz, ctz, IsPowerOf2, NextPowerOf2;

version (BigEndian)
    static assert(false, "TODO: support BigEndian!");

pure nothrow @nogc:


alias big_uint(uint Bits) = big_int!(Bits, false);

struct big_int(uint Bits, bool Signed = true)
{
    static assert((Bits & 63) == 0, "Size must be a multiple of 64 bits");

    alias This = big_int!(Bits, Signed);

    enum num_elements = Bits / 64;

    static if (Signed)
    {
        enum This min = (){ This r; r.ul[$-1] |= 1UL << 63; return r; }();
        enum This max = (){ This r; r.ul[] = ulong.max; r.ul[$-1] ^= 1UL << 63; return r; }();
    }
    else
    {
        enum This min = This();
        enum This max = (){ This r; r.ul[] = ulong.max; return r; }();
    }

    ulong[num_elements] ul;

    this(I)(I i)
        if (isIntegral!I)
    {
        ul[0] = i;
        static if (Bits > 64 && isSignedIntegral!I)
            ul[1..$] = (cast(long)ul[0]) >> 63;
    }

    this(uint N, bool S)(big_int!(N, S) rh)
    {
        static assert(N <= Bits, "Cannot convert to a smaller type!"); // TODO: match DMD error message...
        ul[0..rh.num_elements] = rh.ul;
        static if (N < Bits && S)
            ul[rh.num_elements..$] = (cast(long)rh.ul[$-1]) >> 63;
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

    auto opBinary(string op : "+", uint N, bool S)(big_int!(N, S) rh) const
    {
        Result!(Bits, Signed, N, S) result = void;
        enum elements = result.num_elements;

        static if (N < Bits && S)
            const ulong sext = (cast(long)rh.ul[$-1]) >> 63;
        else static if (Bits < N && Signed)
            const ulong sext = (cast(long)ul[$-1]) >> 63;
        else
            enum sext = 0;

        ulong carry = void;
        static foreach (i; 0 .. elements)
        {{
            static if (i < num_elements)
                ulong l = ul[i];
            else
                alias l = sext;
            static if (i < rh.num_elements)
                ulong r = rh.ul[i];
            else
                alias r = sext;

            ulong sum = l + r;
            if (sum < l)
            {
                static if (i > 0)
                    sum += carry;
                static if (i < elements - 1)
                    carry = 1;
            }
            else static if (i > 0)
            {
                sum += carry;
                static if (i < elements - 1)
                    carry = sum < ul[i];
            }
            else static if (i < elements - 1)
                carry = 0;

            result.ul[i] = sum;
        }}

        return result;
    }

    auto opBinary(string op : "-", uint N, bool S)(big_int!(N, S) rh) const
    {
        Result!(Bits, Signed, N, S) result = void;
        enum elements = result.num_elements;

        static if (N < Bits && S)
            const ulong sext = (cast(long)rh.ul[$-1]) >> 63;
        else static if (Bits < N && Signed)
            const ulong sext = (cast(long)ul[$-1]) >> 63;
        else
            enum sext = 0;

        ulong borrow = void;
        static foreach (i; 0 .. elements)
        {{
            static if (i < num_elements)
                ulong l = ul[i];
            else
                alias l = sext;
            static if (i < rh.num_elements)
                ulong r = rh.ul[i];
            else
                alias r = sext;

            ulong diff = l - r;
            if (diff > l)
            {
                static if (i > 0)
                    diff -= borrow;
                static if (i < elements - 1)
                    borrow = 1;
            }
            else static if (i > 0)
            {
                diff -= borrow;
                static if (i < elements - 1)
                    borrow = diff > ul[i];
            }
            else static if (i < elements - 1)
                borrow = 0;

            result.ul[i] = diff;
        }}

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
