module protocol.mqtt;

import urt.log;
import urt.mem.allocator;
import urt.string;

import manager.console;
import manager.plugin;

import protocol.mqtt.broker;

nothrow @nogc:

class MQTTModule : Module
{
    mixin DeclareModule!"protocol.mqtt";
nothrow @nogc:

    MQTTBroker broker;

    override void init()
    {
        app.console.registerCommand!broker_add("/protocol/mqtt/broker", this, "add");
    }

    override void update()
    {
        if (broker)
            broker.update();
    }

    void broker_add(Session session, ushort listen_port, const(char)[] username, const(char)[] password)
    {
        MQTTBrokerOptions options;
        options.port = listen_port;
        options.clientCredentials ~= MQTTClientCredentials(username: username.makeString(defaultAllocator()), password: password.makeString(defaultAllocator()));

        broker = app.allocator.allocT!MQTTBroker(options);

        writeInfo("MQTT broker listening on port ", listen_port);
    }
}


private:
