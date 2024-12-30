module urt.format.json;

import urt.array;
import urt.conv;
import urt.lifetime;
import urt.mem.allocator;
import urt.string;

nothrow @nogc:


struct JsonParser
{
nothrow @nogc:
    this(Array!char document)
    {
        parse(document.move);
    }

    ~this()
    {
        static void freeNode(ref JsonNode n) @nogc
        {
            if (n.isArray())
            {
                foreach (ref e; n.asArray)
                    freeNode(e);
                defaultAllocator().freeArray(n.value.n[0 .. n.count]);
            }
            else if (n.isObject())
            {
                foreach (k, ref v; n)
                    freeNode(v);
                defaultAllocator().freeArray(n.value.n[0 .. n.count*2]);
            }
        }
        freeNode(root_);
    }

    void parse(Array!char document)
    {
        this.document = document.move;
        const(char)[] text = this.document[].trimFront;
        root_ = parseNode(text);
        assert(text.trimFront.length == 0);
    }

    ref const(JsonNode) root() const
    {
        return root_;
    }

private:
    Array!char document;
    JsonNode root_;

    JsonNode parseNode(ref const(char)[] text)
    {
        text = text.trimFront();

        if (text.empty)
            return JsonNode();
        else if (text.startsWith("null"))
        {
            text = text[4 .. $];
            return JsonNode();
        }
        else if (text.startsWith("true"))
        {
            text = text[4 .. $];
            return JsonNode(flags: JsonNode.Flags.True);
        }
        else if (text.startsWith("false"))
        {
            text = text[5 .. $];
            return JsonNode(flags: JsonNode.Flags.False);
        }
        else if (text[0] == '"')
        {
            assert(text.length > 1);
            size_t i = 1;
            while (i < text.length && text[i] != '"')
            {
                // TODO: we need to collapse the excape sequence, so we need to copy the string somewhere >_<
                //       ...overwrite the source buffer?
                if (text[i] == '\\')
                {
                    assert(i + 1 < text.length);
                    i += 2;
                }
                else
                    i++;
            }
            assert(i < text.length);
            JsonNode node = JsonNode(value: JsonNode.Value(s: text.ptr + 1), count: cast(uint)i - 1, flags: JsonNode.Flags.String);
            text = text[i + 1 .. $];
            return node;
        }
        else if (text[0] == '{' || text[0] == '[')
        {
            JsonNode[64] tmp = void;
            uint n = 0;

            JsonNode[] list;
            uint count = 0;

            bool isArray = text[0] == '[';
            text = text[1 .. $];

            bool expectComma = false;
            while (true)
            {
                text = text.trimFront;
                if (text.length == 0 || text[0] == (isArray ? ']' : '}'))
                    break;
                else if (expectComma)
                {
                    if (text[0] == ',')
                        text = text[1 .. $].trimFront;
                }
                else
                    expectComma = true;

                if (n == tmp.length)
                {
                    if (list.length < count + n)
                        list = defaultAllocator().reallocArray!JsonNode(list, list.length*2 < n*2 ? n*2 : list.length*2);
                    foreach (i; 0 .. n)
                        list[count + i] = tmp[i];
                    count += n;
                    n = 0;
                }

                tmp[n++] = parseNode(text);
                if (!isArray)
                {
                    assert(tmp[n-1].isString());

                    text = text.trimFront;
                    assert(text.length > 0 && text[0] == ':');
                    text = text[1 .. $].trimFront;
                    tmp[n++] = parseNode(text);
                }
            }
            assert(text.length > 0);
            text = text[1 .. $];

            if (list.length < count + n)
                list = defaultAllocator().reallocArray!JsonNode(list, count + n);
            foreach (i; 0 .. n)
                list[count + i] = tmp[i];
            count += n;

            return JsonNode(value: JsonNode.Value(n: list.ptr), count: isArray ? n : n/2, flags: isArray ? JsonNode.Flags.Array : JsonNode.Flags.Object);
        }
        else if (text[0].isNumeric || (text[0] == '-' && text.length > 1 && text[1].isNumeric))
        {
            bool neg = text[0] == '-';
            size_t taken = void;
            ulong div = void;
            ulong value = text[neg .. $].parseUint(&taken, 10, &div);
            assert(taken > 0);
            text = text[taken + neg .. $];

            if (div > 1)
            {
                double d = cast(double)value;
                if (neg)
                    d = -d;
                d /= div;
                return JsonNode(value: JsonNode.Value(d: d), flags: JsonNode.Flags.NumberDouble);
            }
            else
            {
                if (neg)
                {
                    assert(value <= long.max + 1);
                    return JsonNode(value: JsonNode.Value(ul: -cast(long)value), flags: value <= int.max + 1 ? JsonNode.Flags.NumberInt : JsonNode.Flags.NumberInt64);
                }
                else
                {
                    JsonNode.Flags f = JsonNode.Flags.NumberUint64;
                    if (value <= int.max)
                        f |= JsonNode.Flags.IntFlag | JsonNode.Flags.UintFlag | JsonNode.Flags.Int64Flag;
                    else if (value <= uint.max)
                        f |= JsonNode.Flags.UintFlag | JsonNode.Flags.Int64Flag;
                    else if (value <= long.max)
                        f |= JsonNode.Flags.Int64Flag;
                    return JsonNode(value: JsonNode.Value(ul: value), flags: f);
                }
            }
        }
        else
            assert(false, "Invalid JSON!");
    }

}

struct JsonNode
{
nothrow @nogc:
    enum Type : ushort
    {
        Null    = 0,
        False   = 1,
        True    = 2,
        Object  = 3,
        Array   = 4,
        String  = 5,
        Number  = 6,
    }

    Type type() const
        => cast(Type)(flags & Flags.TypeMask);

    bool isNull() const
        => flags == Flags.Null;
    bool isFalse() const
        => flags == Flags.False;
    bool isTrue() const
        => flags == Flags.True;
    bool isBool() const
        => (flags & Flags.BoolFlag) != 0;
    bool isNumber() const
        => (flags & Flags.NumberFlag) != 0;
    bool isInt() const
        => (flags & Flags.IntFlag) != 0;
    bool isUint() const
        => (flags & Flags.UintFlag) != 0;
    bool isLong() const
        => (flags & Flags.Int64Flag) != 0;
    bool isUlong() const
        => (flags & Flags.Uint64Flag) != 0;
    bool isDouble() const
        => (flags & Flags.DoubleFlag) != 0;
    bool isString() const
        => (flags & Flags.StringFlag) != 0;
    bool isArray() const
        => flags == Flags.Array;
    bool isObject() const
        => flags == Flags.Object;

    bool asBool() const
    {
        assert(isBool());
        return flags == Flags.True;
    }

    int asInt() const
    {
        assert(isInt());
        return cast(int)cast(long)value.ul;
    }
    uint asUint() const
    {
        assert(isUint());
        return cast(uint)value.ul;
    }
    long asLong() const
    {
        assert(isLong());
        return cast(long)value.ul;
    }
    ulong asUlong() const
    {
        assert(isUlong());
        return value.ul;
    }

    double asDouble() const
    {
        assert(isNumber());
        if ((flags & Flags.DoubleFlag) != 0)
            return value.d;
        if ((flags & Flags.UintFlag) != 0)
            return cast(double)cast(uint)value.ul;
        if ((flags & Flags.IntFlag) != 0)
            return cast(double)cast(int)cast(long)value.ul;
        if ((flags & Flags.Uint64Flag) != 0)
            return cast(double)value.ul;
        return cast(double)cast(long)value.ul;
    }

    float asFloat() const
        => cast(float)asDouble();

    const(char)[] asString() const
    {
        assert(isString());
        return value.s[0 .. count];
    }

    inout(JsonNode)[] asArray() inout
    {
        assert(isArray());
        return value.n[0 .. count];
    }

    size_t opDollar() const
    {
        assert(isArray());
        return count;
    }

    ref inout(JsonNode) opIndex(size_t i) inout
    {
        assert(isArray());
        assert(i < count);
        return value.n[i];
    }

    inout(JsonNode)* getMember(const(char)[] member) inout
    {
        assert(isObject());
        for (uint i = 0; i < count * 2; i += 2)
        {
            if (value.n[i].asString() == member)
                return value.n + i + 1;
        }
        return null;
    }

    ref inout(JsonNode) opIndex(const(char)[] member) inout
    {
        assert(isObject());
        inout(JsonNode)* m = getMember(member);
        assert(m !is null);
        return *m;
    }

    ref inout(JsonNode) opDispatch(string member)() inout
    {
        inout(JsonNode)* m = getMember(member);
        assert(m !is null);
        return *m;
    }

    int opApply(int delegate(const(char)[] k, ref JsonNode v) @nogc dg)
    {
        int r = 0;
        try
        {
            for (uint i = 0; i < count * 2; i += 2)
            {
                r = dg(value.n[i].asString(), value.n[i + 1]);
                if (r != 0)
                    break;
            }
        }
        catch(Exception e)
        {
            assert(false, "Exception in loop body!");
        }
        return r;
    }

private:
    union Value
    {
        ulong ul;
        double d;
        const(char)* s;
        JsonNode* n;
    }

    Value value;
    uint count;
    Flags flags;

    enum Flags : ushort
    {
        Null            = cast(Flags)Type.Null,
        True            = cast(Flags)Type.True | Flags.BoolFlag,
        False           = cast(Flags)Type.False | Flags.BoolFlag,
        NumberInt       = cast(Flags)Type.Number | Flags.NumberFlag | Flags.IntFlag | Flags.Int64Flag,
        NumberUint      = cast(Flags)Type.Number | Flags.NumberFlag | Flags.UintFlag | Flags.Uint64Flag | Flags.Int64Flag,
        NumberInt64     = cast(Flags)Type.Number | Flags.NumberFlag | Flags.Int64Flag,
        NumberUint64    = cast(Flags)Type.Number | Flags.NumberFlag | Flags.Uint64Flag,
        NumberDouble    = cast(Flags)Type.Number | Flags.NumberFlag | Flags.DoubleFlag,
//        NumberAnyFlag = static_cast<int>(kNumberType) | static_cast<int>(kNumberFlag | kIntFlag | kInt64Flag | kUintFlag | kUint64Flag | kDoubleFlag),
//        ConstStringFlag = static_cast<int>(kStringType) | static_cast<int>(kStringFlag),
//        CopyStringFlag = static_cast<int>(kStringType) | static_cast<int>(kStringFlag | kCopyFlag),
//        ShortStringFlag = static_cast<int>(kStringType) | static_cast<int>(kStringFlag | kCopyFlag | kInlineStrFlag),
        String          = cast(Flags)Type.String | Flags.StringFlag,
        Object          = cast(Flags)Type.Object,
        Array           = cast(Flags)Type.Array,

        BoolFlag        = 0x0008,
        NumberFlag      = 0x0010,
        IntFlag         = 0x0020,
        UintFlag        = 0x0040,
        Int64Flag       = 0x0080,
        Uint64Flag      = 0x0100,
        DoubleFlag      = 0x0200,
        StringFlag      = 0x0400,
        CopyFlag        = 0x0800,
        InlineFlag      = 0x1000,

        TypeMask        = 0x0007,
    }
}


unittest
{
    immutable document = `{
        "nothing": null,
        "name": "John Doe",
        "age": 42,
        "neg": -42,
        "sobig": 8234567890,
        "married": true,
        "worried": false,
        "children": [
            {
                "name": "Jane Doe",
                "age": 12
            },
            {
                "name": "Jack Doe",
                "age": 8
            }
        ]
    }`;

    JsonParser json;
    json.parse(StringLit!document);
    assert(json.root.nothing.isNull);
    assert(json.root.name.asString == "John Doe");
    assert(json.root.age.asUint == 42);
    assert(json.root.neg.asInt == -42);
    assert(json.root.sobig.asLong == 8234567890);
    assert(json.root.married.asBool == true);
    assert(json.root.worried.asBool == false);
    assert(json.root.children.asArray.length == 2);
    assert(json.root.children.asArray[0].name.asString == "Jane Doe");
    assert(json.root.children.asArray[0].age.asInt == 12);
    assert(json.root.children.asArray[1].name.asString == "Jack Doe");
    assert(json.root.children.asArray[1].age.asInt == 8);
}
