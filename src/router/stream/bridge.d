module router.stream.bridge;

public import router.stream;

import urt.log;

class BridgeStream : Stream
{
	this(StreamOptions options, Stream[] streams...)
	{
		super(options);

		this.streams = streams;
	}

	override bool connect()
	{
		// should we connect subordinate streams?
		return true;
	}

	override void disconnect()
	{
		// TODO: Should this disconnect subordinate streams?
	}

	override bool connected()
	{
		// what here?
		return true;
	}

	override string remoteName()
	{
		string name = "bridge[";
		for (size_t i = 0; i < streams.length; ++i)
		{
			if (i > 0)
				name ~= "|";
			name ~= streams[i].remoteName();
		}
		name ~= "]";
		return name;
	}

	override void setOpts(StreamOptions options)
	{
		this.options = options;
	}

	override ptrdiff_t read(ubyte[] buffer)
	{
		size_t read;
		if (buffer.length < inputBuffer.length)
		{
			read = buffer.length;
			buffer[] = inputBuffer[0 .. read];
			inputBuffer = inputBuffer[read .. $];
		}
		else
		{
			read = inputBuffer.length;
			buffer[0 .. read] = inputBuffer[];
			inputBuffer.length = 0;
		}
		return read;
	}

	override ptrdiff_t write(const ubyte[] data)
	{
		foreach (i; 0 .. streams.length)
		{
			ptrdiff_t written = 0;
			while (written < data.length)
			{
				written += streams[i].write(data[written .. 0]);
			}
		}
		return 0;
	}

	override ptrdiff_t pending()
	{
		return inputBuffer.length;
	}

	override ptrdiff_t flush()
	{
		// what this even?
		assert(0);
		foreach (stream; streams)
			stream.flush();
		inputBuffer.length = 0;
		return 0;
	}

	override void poll()
	{
		// TODO: this is shit; polling periodically sucks, and will result in sync issues!
		//       ideally, sleeping threads blocking on a read, fill an input buffer...

		// read all streams, echo to other streams, accumulate input buffer
		foreach (i; 0 .. streams.length)
		{
			ubyte[1024] buf;
			size_t bytes;
			do
			{
				bytes = streams[i].read(buf);

				debug
				{
					if (bytes)
						writeDebugf("From {0}:\n{1}\n", i, cast(void[])buf[0..bytes]);
				}

				if (bytes == 0)
					break;

				foreach (j; 0 .. streams.length)
				{
					if (j == i)
						continue;
					streams[j].write(buf[0..bytes]);
				}

				inputBuffer ~= buf[0..bytes];
			}
			while (bytes < buf.sizeof);
		}
	}

private:
	Stream[] streams;

	ubyte[] inputBuffer;
}
