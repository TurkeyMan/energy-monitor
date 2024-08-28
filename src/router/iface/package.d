module router.iface;

import urt.conv;
import urt.map;
import urt.mem.ring;
import urt.mem.string;
import urt.string;
import urt.string.format;
import urt.time;

import manager.console;
import manager.plugin;

public import router.iface.packet;


enum BufferOverflowBehaviour : byte
{
	DropOldest,	// drop oldest data in buffer
	DropNewest,	// drop newest data in buffer (or don't add new data to full buffer)
	Fail		// cause the call to fail
}

struct PacketFilter
{
	alias FilterCallback = bool delegate(ref const Packet p) nothrow @nogc;

	MACAddress src;
	MACAddress dst;
	ushort etherType;
	ushort enmsSubType;
	ushort vlan;
	FilterCallback customFilter;

	bool match(ref Packet p)
	{
		if (etherType && p.etherType != etherType)
			return false;
		if (enmsSubType && p.etherSubType != enmsSubType)
			return false;
		if (vlan && p.vlan != vlan)
			return false;
		if (src && p.src != src)
			return false;
		if (dst && p.dst != dst)
			return false;
		if (customFilter)
			return customFilter(p);
		return true;
	}
}

struct InterfaceSubscriber
{
	alias IncomingPacketHandler = void delegate(ref const Packet p, BaseInterface i) nothrow @nogc;

	PacketFilter filter;
	IncomingPacketHandler recvPacket;
}

struct InterfaceStatus
{
	MonoTime linkStatusChangeTime;
	bool linkStatus;
	int linkDowns;

	uint sendPackets;
	uint recvPackets;
	ulong sendBytes;
	ulong revcBytes;
}

// MAC: 02:xx:xx:ra:nd:yy
//      02:13:37:xx:xx:yy
//      02:AC:1D:xx:xx:yy
//      02:C0:DE:xx:xx:yy
//      02:BA:BE:xx:xx:yy
//      02:DE:AD:xx:xx:yy
//      02:FE:ED:xx:xx:yy
//      02:B0:0B:xx:xx:yy

class BaseInterface
{
	InterfaceModule.Instance mod_iface;

	String name;
	CacheString type;

	MACAddress mac;
	Map!(MACAddress, BaseInterface) macTable;

	InterfaceSubscriber[] subscribers;

	InterfaceStatus status;

	BufferOverflowBehaviour sendBehaviour;
	BufferOverflowBehaviour recvBehaviour;

	this(InterfaceModule.Instance m, String name, const(char)[] type) nothrow @nogc
	{
		import core.lifetime;

		this.mod_iface = m;
		this.name = name.move;
		this.type = type.addString();

		mac = generateMacAddress();
		addAddress(mac, this);
	}

	void update()
	{
	}

	ref const(InterfaceStatus) getStatus() const
		=> status;

	void subscribe(InterfaceSubscriber.IncomingPacketHandler packetHandler, PacketFilter filter)
	{
		subscribers ~= InterfaceSubscriber(filter, packetHandler);
	}

	abstract bool send(ref const Packet packet) nothrow @nogc;

	final void addAddress(MACAddress mac, BaseInterface iface) nothrow @nogc
	{
		assert(mac !in macTable, "MAC address already in use!");
		macTable[mac] = iface;
	}

	final void removeAddress(MACAddress mac) nothrow @nogc
	{
		macTable.remove(mac);
	}

	final BaseInterface findMacAddress(MACAddress mac) nothrow @nogc
	{
		BaseInterface* i = mac in macTable;
		if (i)
			return *i;
		return null;
	}

package:
	Packet[] sendQueue;

	MACAddress generateMacAddress() pure nothrow @nogc
	{
		enum ushort MAGIC = 0x1337;

		uint crc = name.ethernetCRC();
		MACAddress addr = MACAddress(0x02, MAGIC >> 8, MAGIC & 0xFF, crc & 0xFF, (crc >> 8) & 0xFF, (crc >> 16) & 0xFF);
		if (addr.b[5] < 100 || addr.b[5] >= 240)
			addr.b[5] ^= 0x80;
		return addr;
	}

	void dispatch(ref Packet packet)
	{
		// update the stats
		++status.recvPackets;
		status.revcBytes += packet.length;

		// check if we ever saw the sender before...
		if (findMacAddress(packet.src) is null)
			addAddress(packet.src, this);

		foreach (ref subscriber; subscribers)
		{
			if (subscriber.filter.match(packet))
				subscriber.recvPacket(packet, this);
		}
	}
}


class InterfaceModule : Plugin
{
	mixin RegisterModule!"interface";

	class Instance : Plugin.Instance
	{
		mixin DeclareInstance;

		BaseInterface[const(char)[]] interfaces;

		override void init()
		{
		}

		override void update()
		{
			foreach (i; interfaces)
				i.update();
		}

		const(char)[] generateInterfaceName(const(char)[] prefix)
		{
			if (prefix !in interfaces)
				return prefix;
			for (size_t i = 0; i < ushort.max; i++)
			{
				const(char)[] name = tconcat(prefix, i);
				if (name !in interfaces)
					return name;
			}
			return null;
		}

		final void addInterface(BaseInterface iface)
		{
			assert(iface.name[] !in interfaces, "Interface already exists");
			interfaces[iface.name[]] = iface;
		}

		final void removeInterface(BaseInterface iface)
		{
			assert(iface.name[] in interfaces, "Interface not found");
			interfaces.remove(iface.name[]);
		}

		final BaseInterface findInterface(const(char)[] name)
		{
			foreach (i; interfaces)
				if (i.name[] == name[])
					return i;
			return null;
		}

	private:

	}
}


private: