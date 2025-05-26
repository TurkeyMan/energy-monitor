module protocol.http.websocket;

import urt.array;
import urt.digest.sha;
import urt.encoding;
import urt.lifetime;
import urt.string;

import protocol.http.message;
import protocol.http.server;

import router.stream;

nothrow @nogc:


enum WebSocketExtensions : ubyte
{
    None = 0,
    PerMessageCompression = 1 << 0,
    ClientMaxWindowBits = 1 << 1,
//    PerMessageCompression = "permessage-deflate",
//    ServerPush = "server-push",
//    ClientPush = "client-push",
//    ChannelId = "channel-id",
//    ChannelIdClient = "channel-id-client",
//    ChannelIdServer = "channel-id-server",
//    ChannelIdClientServer = "channel-id-client-server"
}


class WebSocket : Stream
{
nothrow @nogc:

    this(String name, Stream stream)
    {
        super(name.move, "websocket", StreamOptions.None);
        this.stream = stream;
    }

    ~this()
    {
        // TODO: what is the proper way to cleanup streams?
//        defaultAllocator.freeT(stream);
    }

    override bool connect()
    {
        // TODO: websockets which are explicitly connected may support this, but websockets created by WebsocketServer can't connect()...
        return stream.connect();
    }

    override void disconnect()
    {
        stream.disconnect();
    }

    override bool connected()
        => stream.connected();

    override const(char)[] remoteName()
        => stream.remoteName(); // TODO: maybe we should report the value from the `Origin` header?

    override void setOpts(StreamOptions options)
        => stream.setOpts(options);

    override ptrdiff_t read(void[] buffer)
    {
        ubyte[1024] tmp;
        size_t offset = 0;
        size_t read = 0;

        ptrdiff_t bytes = stream.read(tmp[tail.length .. $]);
        if (bytes <= 0)
            return bytes; // TODO: handle errors

        // prepend tail...
        tmp[0 .. tail.length] = tail[];
        bytes += tail.length;
        tail.clear();

        if (bytes < 2)
            goto stash_for_later;
        offset += 2;

        ubyte[] msg = tmp[0 .. bytes];

        bool fin = msg[0] >> 7; // FIN
        ubyte rsv = msg[0] >> 4; // RSV
        ubyte opcode = msg[0] & 0xF; // OPCODE
        bool mask = msg[1] >> 7; // MASK
        ulong payloadLen = msg[1] & 0x7F;

        if (payloadLen == 0xFE)
        {
            if (bytes < offset + 2)
                goto stash_for_later;
            payloadLen = msg[2 .. 4].bigEndianToNative!ushort;
            offset += 2;
        }
        else if (payloadLen == 0xFF)
        {
            if (bytes < offset + 8)
                goto stash_for_later;
            payloadLen = msg[2 .. 10].bigEndianToNative!ulong;
            offset += 8;
        }

        if (mask)
        {
            if (bytes < offset + 4)
                goto stash_for_later;
            ubyte[] maskKey = msg[offset .. offset + 4];
            offset += 4;
            for (size_t i = 0; i < payloadLen; ++i)
                msg[offset + i] ^= maskKey[i & 3];
        }

        switch (opcode)
        {
            case 0: // continuation frame
                break;
            case 1: // text frame
                break;
            case 2: // binary frame
                break;
            case 8: // connection close
                break;
            case 9: // ping
                break;
            case 10: // pong
                break;
            default:
                assert(false, "TODO: handle unknown opcode");
                // TODO: should we terminate the stream, or try and re-sync?
        }

//        buffer

        return read;

    stash_for_later:
        tail = msg[offset .. $];
        return read;
    }

    override ptrdiff_t write(const void[] data)
    {
        assert(false, "TODO");

        return stream.write(data);
    }

    override ptrdiff_t pending()
        => stream.pending();

    override ptrdiff_t flush()
        => stream.flush();

    override void update()
    {
        stream.update();
    }

private:
    Stream stream;
    WebSocketExtensions extensions;
    String protocol;
    Array!ubyte tail;
}

class WebSocketServer
{
nothrow @nogc:

    alias NewConnection = void delegate(WebSocket client, void* userData) nothrow @nogc;

    this(String name, HTTPServer server, const(char[]) uri, NewConnection callback, void* userData)
    {
        this.name = name.move;
        this.server = server;
        this.connectionCallback = callback;
        this.userData = userData;

        if (uri)
            server.addHandler(HTTPMethod.GET, uri, &this.handleRequest);
        else
            defaultHandler = server.hookGlobalHandler(&this.handleRequest);
    }

    int handleRequest(ref const HTTPMessage request, ref Stream stream)
    {
        if (request.header("Upgrade") == "websocket")
        {
            // validate version (just 13?)
            // else, reply "426 Upgrade Required" with header `Sec-WebSocket-Version` set to an accepted version

            // validate the resource name (path) or report "404 Not Found"

            // validate the connection is accepted, reply "403 Forbodden" if not
            //... `Origin` filtering?

            // check subprotocol from `Sec-WebSocket-Protocol`...?
            // if server accepts, must reply with acceptable `Sec-WebSocket-Protocol` header

            import urt.mem.allocator;
            import urt.mem.temp;
            String n = tconcat(name, ++numConnections).makeString(defaultAllocator);
            WebSocket ws = defaultAllocator.allocT!WebSocket(n.move, stream);

            if (const(char)[] proto = request.header("Sec-WebSocket-Protocol"))
                ws.protocol = proto.makeString(defaultAllocator);

            ubyte requestExtensions;
            if (const(char)[] ext = request.header("Sec-WebSocket-Extensions"))
            {
                each_ext: while (const(char)[] e = ext.split!';'.trim)
                {
                    foreach (i, extName; g_webSocketExtensions[1 .. $])
                    {
                        if (e[] == extName[])
                        {
                            requestExtensions |=  cast(ubyte)(1 << i);
                            continue each_ext;
                        }
                    }
                    // unknown extension
                    assert(false, "What to do?!");
                }
            }
            // TODO: I think we're meant to reply with the extensions that we accepted?
//            ws.extensions = cast(WebSocketExtensions)requestExtensions;

            // we must generate the accept key...
            // this is literally the STUPIDEST spec i've ever read in all my years!!
            MutableString!0 key = request.header("Sec-WebSocket-Key").trim;
            key ~= "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
            SHA1Context shaState;
            shaInit(shaState);
            shaUpdate(shaState, key[]);
            auto digest = shaFinalise(shaState);
            enum EncodeLen = base64_encode_length(digest.length);

            // complete the handshake...
            MutableString!0 response;
            httpStatusLine(request.httpVersion, 101, "Switching Protocols", response);
            response ~= "Upgrade: websocket\r\n" ~
                        "Connection: Upgrade\r\n" ~
                        "Sec-WebSocket-Accept: ";
            base64_encode(digest, response.extend(EncodeLen));
            response ~= "\r\n" ~
//                        "Sec-WebSocket-Protocol: chat, superchat\r\n" ~
                        "\r\n";
            stream.write(response);

            // claim the stream... somehow?
            ws.stream = stream;
            stream = null; // TODO: better strategy to notify the caller that we claimed the stream!

            connectionCallback(ws, userData);
            return 0;
        }

        if (defaultHandler)
            return defaultHandler(request, stream);
        return -1;
    }

    String name;
    HTTPServer server;

private:
    HTTPServer.RequestHandler defaultHandler;
    NewConnection connectionCallback;
    void* userData;
    int numConnections;
}


private:

__gshared immutable string[__traits(allMembers, WebSocketExtensions).length] g_webSocketExtensions = [
    null,
    "permessage-deflate",
    "client_max_window_bits"
//    "server-push",
//    "client-push",
//    "channel-id",
//    "channel-id-client",
//    "channel-id-server",
//    "channel-id-client-server"
];
