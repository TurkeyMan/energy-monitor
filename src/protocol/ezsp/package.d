module protocol.ezsp;

import urt.endian;
import urt.lifetime;
import urt.map;
import urt.mem.allocator;
import urt.string;

import manager.console.command;
import manager.console.function_command : FunctionCommandState;
import manager.console.session;
import manager.plugin;

import protocol.ezsp.client;

import router.stream;

nothrow @nogc:


class EZSPProtocolModule : Module
{
    mixin DeclareModule!"protocol.ezsp";
nothrow @nogc:

    Map!(const(char)[], EZSPClient) clients;

    override void init()
    {
        app.console.registerCommand!client_add("/protocol/ezsp/client", this, "add");
    }

    EZSPClient getClient(const(char)[] client)
    {
        if (auto c = client in clients)
            return *c;
        return null;
    }

    override void update()
    {
        foreach(name, client; clients)
            client.update();
    }

    void client_add(Session session, const(char)[] name, const(char)[] stream)
    {
        auto mod_stream = app.moduleInstance!StreamModule;

        // is it an error to not specify a stream?
        assert(stream, "'stream' must be specified");

        Stream s = mod_stream.getStream(stream);
        if (!s)
        {
            session.writeLine("Stream does not exist: ", stream);
            return;
        }

        if (name.empty)
            mod_stream.generateStreamName("ezsp");

        NoGCAllocator a = app.allocator;

        String n = name.makeString(a);
        EZSPClient client = a.allocT!EZSPClient(n.move, s);
        clients.insert(client.name[], client);

//        writeInfof("Create Serial stream '{0}' - device: {1}@{2}", name, device, params.baudRate);
    }
}


size_t ezspSerialise(T)(ref T data, ubyte[] buffer)
{
    static assert(!is(T == class) && !is(T == interface) && !is(T == U*, U), T.stringof ~ " is not POD");

    static if (is(T == struct))
    {
        size_t bytes = 0;
        alias members = data.tupleof;
        static foreach(i; 0 .. members.length)
        {{
            size_t len = ezspSerialise(members[i], buffer[bytes..$]);
            if (len == 0)
                return 0;
            bytes += len;
        }}
        return bytes;
    }
    else static if (is(T == ubyte[N], size_t N))
    {
        if (buffer.length < N)
            return 0;
        buffer[0 .. N] = data;
        return N;
    }
    else static if (is(T : const(ubyte)[]))
    {
        assert(data.length <= 255, "Data must be <= 255 bytes");
        if (buffer.length < 1 + data.length)
            return 0;
        buffer[0] = cast(ubyte)data.length;
        buffer[1 .. 1 + data.length] = data[];
        return 1 + data.length;
    }
    else
    {
        if (buffer.length < T.sizeof)
            return 0;
        buffer[0 .. T.sizeof] = nativeToLittleEndian(data);
        return T.sizeof;
    }
}

size_t ezspDeserialise(T)(const(ubyte)[] data, out T t)
{
    static assert(!is(T == class) && !is(T == interface) && !is(T == U*, U), T.stringof ~ " is not POD");

    static if (is(T == struct))
    {
        size_t offset = 0;
        alias tup = t.tupleof;
        static foreach(i; 0..tup.length)
        {{
            size_t took = data.ptr[offset..data.length].ezspDeserialise(tup[i]);
            if (took == 0)
                return 0;
            offset += took;
        }}
        return offset;
    }
    else static if (is(T == ubyte[N], size_t N))
    {
        if (data.length < N)
            return 0;
        t = data.ptr[0 .. N];
        return N;
    }
    else static if (is(T : const(ubyte)[]))
    {
        if (data.length < 1 || data.length < 1 + data[0])
            return 0;
        t = (data.ptr + 1)[0 .. data[0]];
        return 1 + t.length;
    }
    else
    {
        if (data.length < T.sizeof)
            return 0;
        t = data.ptr[0 .. T.sizeof].littleEndianToNative!T;
        return T.sizeof;
    }
}
