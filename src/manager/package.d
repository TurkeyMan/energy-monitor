module manager;

import urt.array;
import urt.lifetime : move;
import urt.map;
import urt.mem.allocator;
import urt.mem.string;
import urt.string;

import manager.component;
import manager.console;
import manager.device;
import manager.plugin;
import manager.system;

public static import manager.pcap;

nothrow @nogc:


__gshared Application g_app = null;

Application createApplication()
{
    return defaultAllocator().allocT!Application();
}

void shutdownApplication()
{
    defaultAllocator().freeT(g_app);
}

Mod getModule(Mod)()
    if (is(Mod : Module))
{
    __gshared Mod moduleInstance = null;
    if (!moduleInstance)
        moduleInstance = cast(Mod)g_app.moduleInstance(Mod.ModuleName);
    return moduleInstance;
}


class Application
{
nothrow @nogc:

    String name;

    NoGCAllocator allocator;
    NoGCAllocator tempAllocator;

    Array!Module modules;

    Console console;

    Map!(const(char)[], Device) devices;

    // database...

    this()
    {
        import urt.mem;

        allocator = defaultAllocator;
        tempAllocator = tempAllocator;

        assert(!g_app, "Application already created!");
        g_app = this;

        console = Console(this, String("console".addString), Mallocator.instance);

        console.setPrompt(StringLit!"enermon > ");

        console.registerCommand!log_level("/system", this);
        console.registerCommand!set_hostname("/system", this);

        console.registerCommand!device_print("/device", this, "print");

        registerModules(this);
    }

    ~this()
    {
        g_app = null;
    }

    void registerModule(Module mod)
    {
        import urt.string.format;

        foreach (m; modules)
            assert(m.moduleName[] != mod.moduleName, tconcat("Module '", mod.moduleName, "' already registered!"));

        mod.moduleId = modules.length;
        modules ~= mod;

        mod.init();
    }

    Module moduleInstance(const(char)[] name) pure
    {
        foreach (i; 0 .. modules.length)
            if (modules[i].moduleName[] == name[])
                return modules[i];
        return null;
    }

    Mod moduleInstance(Mod)() pure
        if (is(Mod : Module))
    {
        return cast(Mod)moduleInstance(Mod.ModuleName);
    }

    Device findDevice(const(char)[] deviceId) pure
    {
        if (Device* d = deviceId[] in devices)
            return *d;
        return null;
    }

    Component findComponent(const(char)[] name) pure
    {
        const(char)[] deviceName = name.split!'.';
        if (Device* d = deviceName[] in devices)
            return name.empty ? *d : (*d).findComponent(name);
        return null;
    }

    void update()
    {
        foreach (m; modules)
            m.preUpdate();

        foreach (m; modules)
            m.update();

        import urt.async : asyncUpdate;
        asyncUpdate();

        // TODO: polling is pretty lame! data connections should be in threads and receive data immediately
        // processing should happen in a processing thread which waits on a semaphore for jobs in a queue (submit from comms threads?)
//        foreach (server; servers)
//            server.poll();
        foreach (device; devices.values)
            device.update();

        foreach (m; modules)
            m.postUpdate();
    }


    // /device/print command
    import urt.meta.nullable;
    void device_print(Session session, Nullable!(const(char)[]) _scope)
    {
        if (_scope)
        {
            // split on dots...
        }

        void printComponent(Component c, int indent)
        {
            session.writef("{'', *0}{1}: {2} [{3}]\n", indent, c.id, c.name, c.template_);
            foreach (e; c.elements)
                session.writef("{'', *8}  {0}{@5, ?4}: {2}{@7, ?6}\n", e.id, e.name, e.latest, e.unit, e.name.length > 0, " ({1})", e.unit.length > 0, " [{3}]", indent);
            foreach (c2; c.components)
                printComponent(c2, indent + 2);
        }

        const(char)[] newLine = "";
        foreach (dev; devices.values)
        {
            session.writeLine(newLine, dev.id, ": ", dev.name);
            newLine = "\n";
            foreach (c; dev.components)
                printComponent(c, 2);
        }


/+
        import urt.util;

        size_t nameLen = 4;
        size_t typeLen = 4;
        foreach (i, iface; interfaces)
        {
            nameLen = max(nameLen, iface.name.length);
            typeLen = max(typeLen, iface.type.length);

            // TODO: MTU stuff?
        }

        session.writeLine("Flags: R - RUNNING; S - SLAVE");
        if (stats)
        {
            size_t rxLen = 7;
            size_t txLen = 7;
            size_t rpLen = 9;
            size_t tpLen = 9;
            size_t rdLen = 7;
            size_t tdLen = 7;

            foreach (i, iface; interfaces)
            {
                rxLen = max(rxLen, iface.getStatus.recvBytes.formatInt(null));
                txLen = max(txLen, iface.getStatus.sendBytes.formatInt(null));
                rpLen = max(rpLen, iface.getStatus.recvPackets.formatInt(null));
                tpLen = max(tpLen, iface.getStatus.sendPackets.formatInt(null));
                rdLen = max(rdLen, iface.getStatus.recvDropped.formatInt(null));
                tdLen = max(tdLen, iface.getStatus.sendDropped.formatInt(null));
            }

            session.writef(" ID    {0, *1}  {2, *3}  {4, *5}  {6, *7}  {8, *9}  {10, *11}  {12, *13}\n",
                           "NAME", nameLen,
                           "RX-BYTE", rxLen, "TX-BYTE", txLen,
                           "RX-PACKET", rpLen, "TX-PACKET", tpLen,
                           "RX-DROP", rdLen, "TX-DROP", tdLen);

            size_t i = 0;
            foreach (iface; interfaces)
            {
                session.writef("{0, 3} {1}{2} {3, *4}  {5, *6}  {7, *8}  {9, *10}  {11, *12}  {13, *14}  {15, *16}\n",
                               i, iface.getStatus.linkStatus ? 'R' : ' ', iface.master ? 'S' : ' ',
                               iface.name, nameLen,
                               iface.getStatus.recvBytes, rxLen, iface.getStatus.sendBytes, txLen,
                               iface.getStatus.recvPackets, rpLen, iface.getStatus.sendPackets, tpLen,
                               iface.getStatus.recvDropped, rdLen, iface.getStatus.sendDropped, tdLen);
                ++i;
            }
        }
        else
        {
            session.writef(" ID    {0, *1}  {2, *3}  MAC-ADDRESS\n", "NAME", nameLen, "TYPE", typeLen);
            size_t i = 0;
            foreach (iface; interfaces)
            {
                session.writef("{0, 3} {6}{7}  {1, *2}  {3, *4}  {5}\n", i, iface.name, nameLen, iface.type, typeLen, iface.mac, iface.getStatus.linkStatus ? 'R' : ' ', iface.master ? 'S' : ' ');
                ++i;
            }
        }
+/
    }
}
