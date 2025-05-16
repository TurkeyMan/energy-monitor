module protocol.http.server;

import urt.array;
import urt.conv;
import urt.encoding;
import urt.kvp;
import urt.lifetime;
import urt.mem.allocator;
import urt.string;
import urt.string.format : tconcat;
import urt.time;

import manager;
import manager.base;

import protocol.http;
import protocol.http.message;

import router.stream.tcp;
import router.iface;

nothrow @nogc:


class HTTPServer
{
nothrow @nogc:

    alias RequestHandler = int delegate(ref const HTTPMessage, Stream stream) nothrow @nogc;

    const String name;

    this(String name, BaseInterface , ushort port, RequestHandler defaultRequestHandler)
    {
        const(char)[] server_name = getModule!TCPStreamModule.tcp_servers.generateName(name);

        server = getModule!TCPStreamModule.tcp_servers.create(server_name.makeString(defaultAllocator), ObjectFlags.Dynamic);
        server.port = port;
        server.setConnectionCallback(&acceptConnection, null);

        this.name = name.move;
        this.defaultRequestHandler = defaultRequestHandler;
    }

    ~this()
    {
        server.destroy();
    }

    bool addHandler(HTTPMethod method, const(char)[] uriPrefix, RequestHandler requestHandler)
    {
        foreach (ref h; handlers)
        {
            // if a higher level handler already exists, we can't add this handler
            if (h.method == method && uriPrefix.startsWith(h.uriPrefix))
                return false;
        }

        handlers ~= Handler(method, uriPrefix.makeString(defaultAllocator), requestHandler);
        return true;
    }

    RequestHandler hookGlobalHandler(RequestHandler requestHandler)
    {
        RequestHandler old = defaultRequestHandler;
        defaultRequestHandler = requestHandler;
        return old;
    }

    void update()
    {
        for (size_t i = 0; i < sessions.length; )
        {
            int result = sessions[i].update();
            if (result != 0)
            {
                defaultAllocator().freeT(sessions[i]);
                sessions.remove(i);
            }
            else
                ++i;
        }
    }

package:
    TCPServer server;
    Array!(Session*) sessions;
    RequestHandler defaultRequestHandler;

    void acceptConnection(TCPStream stream, void*)
    {
        sessions.emplaceBack(defaultAllocator().allocT!Session(this, stream));
    }

private:
    struct Handler
    {
        HTTPMethod method;
        String uriPrefix;
        RequestHandler requestHandler;
    }

    Array!Handler handlers;

    struct Session
    {
    nothrow @nogc:

        this(HTTPServer server, Stream stream)
        {
            this.server = server;
            this.stream = stream;
            parser = HTTPParser(&requestCallback);
        }

        int update()
        {
            if (!stream)
                return -1;
            int result = parser.update(stream);
            if (result != 0)
            {
                stream.destroy();
                return result;
            }

            return 0;
        }

        int requestCallback(ref const HTTPMessage request)
        {
            foreach (ref h; server.handlers)
            {
                if (request.method == h.method && request.requestTarget.startsWith(h.uriPrefix))
                    return h.requestHandler(request, stream);
            }
            return server.defaultRequestHandler(request, stream);
        }

        HTTPServer server;
        ObjectRef!Stream stream;

    private:
        HTTPParser parser;
    }
}
