module urt.meta;


alias Alias(alias a) = a;
alias Alias(T) = T;

alias AliasSeq(TList...) = TList;

template IntForWidth(size_t width, bool signed = false)
{
    static if (width <= 8 && !signed)
        alias IntForWidth = ubyte;
    else static if (width <= 8 && signed)
        alias IntForWidth = byte;
    else static if (width <= 16 && !signed)
        alias IntForWidth = ushort;
    else static if (width <= 16 && signed)
        alias IntForWidth = short;
    else static if (width <= 32 && !signed)
        alias IntForWidth = uint;
    else static if (width <= 32 && signed)
        alias IntForWidth = int;
    else static if (width <= 64 && !signed)
        alias IntForWidth = ulong;
    else static if (width <= 64 && signed)
        alias IntForWidth = long;
}

template STATIC_MAP(alias fun, args...)
{
    alias STATIC_MAP = AliasSeq!();
    static foreach (arg; args)
        STATIC_MAP = AliasSeq!(STATIC_MAP, fun!arg);
}

template STATIC_FILTER(alias filter, args...)
{
    alias STATIC_FILTER = AliasSeq!();
    static foreach (arg; args)
        static if (filter!arg)
            STATIC_FILTER = AliasSeq!(STATIC_FILTER, arg);
}

template static_index_of(args...)
    if (args.length >= 1)
{
    enum static_index_of = {
        static foreach (idx, arg; args[1 .. $])
            static if (is_same!(args[0], arg))
                // `if (__ctfe)` is redundant here but avoids the "Unreachable code" warning.
                if (__ctfe) return idx;
        return -1;
    }();
}

template InterleaveSeparator(alias sep, Args...)
{
    alias InterleaveSeparator = AliasSeq!();
    static foreach (i, A; Args)
        static if (i > 0)
            InterleaveSeparator = AliasSeq!(InterleaveSeparator, sep, A);
        else
            InterleaveSeparator = AliasSeq!(A);
}


template EnumKeys(E)
{
    static assert(is(E == enum), "EnumKeys only works with enums!");
    __gshared immutable string[EnumStrings.length] EnumKeys = [ EnumStrings ];
    private alias EnumStrings = __traits(allMembers, E);
}

E enum_from_string(E)(const(char)[] key)
    if (is(E == enum))
{
    foreach (i, k; EnumKeys!E)
        if (key[] == k[])
            return cast(E)i;
    return cast(E)-1;
}


private:

template is_same(alias a, alias b)
{
    static if (!is(typeof(&a && &b)) // at least one is an rvalue
               && __traits(compiles, { enum is_same = a == b; })) // c-t comparable
        enum is_same = a == b;
    else
        enum is_same = __traits(isSame, a, b);
}
// TODO: remove after https://github.com/dlang/dmd/pull/11320 and https://issues.dlang.org/show_bug.cgi?id=21889 are fixed
template is_same(A, B)
{
    enum is_same = is(A == B);
}
