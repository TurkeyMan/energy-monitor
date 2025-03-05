module protocol.mqtt.broker;

import urt.array;
import urt.lifetime;
import urt.map;
import urt.mem.allocator;
import urt.string;
import urt.time;

import protocol.mqtt.client;

import router.stream;
import router.stream.tcp;

nothrow @nogc:


struct MQTTClientCredentials
{
	this(this) @disable;

	String username;
	String password;
	Array!String whitelist;
	Array!String blacklist;
}

struct MQTTBrokerOptions
{
nothrow @nogc:
    this(this) @disable;
    this(ref MQTTBrokerOptions rh)
    {
        this.port = rh.port;
        this.flags = rh.flags;
        this.clientCredentials = rh.clientCredentials;
        this.clientTimeoutOverride = rh.clientTimeoutOverride;
    }

	enum Flags
	{
		None = 0,
		AllowAnonymousLogin = 1 << 0,
	}

	ushort port = 1883;
	Flags flags = Flags.None;
	Array!MQTTClientCredentials clientCredentials;
	uint clientTimeoutOverride = 0;	// maximum time since last contact before client is presumed awol
}

struct MQTTSession
{
	this(this) @disable;

	struct Subscription
	{
		String topic;
		ubyte options;
	}

	String identifier;
	Client* client;

	uint sessionExpiryInterval = 0;

	MonoTime closeTime;

	Array!Subscription subs;
	Map!(const(char)[], Subscription*) subsByFilter;

	// last will and testament
	String willTopic;
	Array!ubyte willMessage;
	Array!ubyte willProps;
	uint willDelay;
	ubyte willFlags;
	bool willSent;

	// publish state
	ushort packetId = 1;

	// TODO: pending messages...
	ubyte[] pendingMessages;
}

class MQTTBroker
{
nothrow @nogc:
	const MQTTBrokerOptions options;

	TCPServer server;
	Array!Client clients;
	Map!(const(char)[], MQTTSession) sessions;

	// local subs
	// network subs

	// retained values
	struct Value
	{
		Map!(String, Value) children;
		Array!ubyte data;
		Array!ubyte properties;
		ubyte flags;
	}
	Value root;

	this(ref MQTTBrokerOptions options)
	{
		this.options = options;
		server = defaultAllocator().allocT!TCPServer(StringLit!"mqtt", options.port, &newConnection);
	}

	void start()
	{
		server.start();
	}

	void stop()
	{
		server.stop();
	}

	void update()
	{
		server.update();

		// update clients
		for (size_t i = 0; i < clients.length; ++i)
		{
			if (!clients[i].update())
			{
				// destroy client...
				clients[i].terminate();
				clients.removeSwapLast(i);
			}
		}

		// update sessions
		MonoTime now = getTime();
		const(char)[][16] itemsToRemove;
		size_t numItemsToRemove = 0;
		foreach (ref session; sessions)
		{
			if (session.client)
				continue;

			if (session.sessionExpiryInterval != 0xFFFFFFFF)
			{
				if (now - session.closeTime >= session.sessionExpiryInterval.seconds)
				{
					// session expired
					if (numItemsToRemove == 16)
						break;
					itemsToRemove[numItemsToRemove++] = session.identifier;
				}
			}
		}
		foreach (i; 0 .. numItemsToRemove)
			sessions.remove(itemsToRemove[i]);
	}

	void publish(const(char)[] client, ubyte flags, const(char)[] topic, const(ubyte)[] payload, const(ubyte)[] properties = null)
	{
		Value* getRecord(Value* val, const(char)[] topic)
		{
			char sep;
			const(char)[] level = topic.split!'/'(sep);
			Value* child = level in val.children;
			if (!child)
				child = val.children.insert(level.makeString(defaultAllocator()), Value());
			if (sep == 0)
				return child;
			return getRecord(child, topic);
		}

		void deleteRecord(Value* val, const(char)[] topic) nothrow @nogc
		{
			char sep;
			const(char)[] level = topic.split!'/'(sep);
			Value* child = level in val.children;
			if (sep == 0)
				child.data = null;
			else if(child)
				deleteRecord(child, topic);
			if (child.children.empty)
				val.children.remove(level);
		}

		// retain message and/or push to subscribers...
		ubyte qos = (flags >> 1) & 3;
		bool retain = (flags & 1) != 0;
		bool dup = (flags & 8) != 0;

		if (payload.empty)
		{
			deleteRecord(&root, topic);
			return;
		}

		if (retain)
		{
			Value* value = getRecord(&root, topic);
			if (value)
			{
				value.data = payload[];
				if (properties)
					value.properties = properties[];
				else
					value.properties = null;
				value.flags = flags;
			}
		}

		// now notify all the other dubscribers...
		// TODO: scan subscriptions and send...

	}

	void subscribe(Client client, const(char)[] topic)
	{
		// add subscription...
	}

package:
	void destroySession(ref MQTTSession session)
	{
		sendLWT(session);

		session.client = null;
		session.subs = null;
		session.subsByFilter.clear();
		session.willTopic = null;
		session.willMessage = null;
		session.willProps = null;
		session.willDelay = 0;
		session.willFlags = 0;
		session.packetId = 1;
	}

	void sendLWT(ref MQTTSession session)
	{
		if (!session.willTopic || session.willSent)
			return;
		publish(session.identifier, session.willFlags, session.willTopic, session.willMessage[], session.willProps[]);
		session.willSent = true;
	}

private:
	void newConnection(TCPStream client, void* userData)
	{
		client.setOpts(StreamOptions.NonBlocking);
		clients ~= Client(this, client);
	}
}
