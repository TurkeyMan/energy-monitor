module protocol.http.websocket;

import urt.lifetime;
import urt.string;

import protocol.http.message;
import protocol.http.server;

import router.stream;

nothrow @nogc:


enum WebsocketExtensions : ubyte
{
    PerMessageCompression = 1,
//    PerMessageCompression = "permessage-deflate",
//    ServerPush = "server-push",
//    ClientPush = "client-push",
//    ChannelId = "channel-id",
//    ChannelIdClient = "channel-id-client",
//    ChannelIdServer = "channel-id-server",
//    ChannelIdClientServer = "channel-id-client-server"
}


class Websocket : Stream
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
        => stream.read(buffer);

    override ptrdiff_t write(const void[] data)
        => stream.write(data);

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
    WebsocketExtensions extensions;
    ubyte[16] key;
}

class WebsocketServer
{
nothrow @nogc:

    alias NewConnection = void delegate(Stream client, void* userData) nothrow @nogc;

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

    int handleRequest(ref const HTTPMessage request, Stream stream)
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
            Websocket ws = defaultAllocator.allocT!Websocket(n.move, stream);

            import urt.encoding;
            if (const(char)[] key = request.header("Sec-WebSocket-Key"))
                key.base64_decode(ws.key);

            if (const(char)[] ext = request.header("Sec-WebSocket-Extensions"))
            {
                while (const(char)[] e = ext.split!','.trim)
                {
                    switch (e)
                    {
                        case "permessage-deflate":
                            ws.extensions |= WebsocketExtensions.PerMessageCompression;
                            break;
                        //...
                        default:
                            // unknown extension
                            break;
                    }
                }
            }
            // TODO: I think we're meant to reply with the extensions that we accepted?

            // complete the handshake...
            // respon with "101 Switching Protocols" and headers: ...?

            // claim the stream... somehow?

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
