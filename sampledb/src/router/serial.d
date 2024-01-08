module router.serial;

import std.format;
import std.stdio;


struct SerialParams
{
    this(int baud)
	{
        this.baudRate = baud;
	}

    int baudRate = 9600;
    int dataBits = 8;
    int stopBits = 1;
    // parity?
}

version(Windows)
{
    import core.sys.windows.windows;
    import std.conv : to;
    import std.string : toStringz;

    struct SerialPort
	{
        HANDLE hCom = INVALID_HANDLE_VALUE;

        void open(string device, ref in SerialParams params = SerialParams())
		{
            wchar[256] buf;
			wstring wstr = device.to!wstring;
            assert(wstr.length < buf.length);
            buf[0..wstr.length] = wstr[];
            buf[wstr.length] = 0;

            hCom = CreateFile(buf.ptr, GENERIC_READ | GENERIC_WRITE, 0, null, OPEN_EXISTING, 0, null);
            if (hCom == INVALID_HANDLE_VALUE)
			{
                writeln("CreateFile failed with error %d.\n", GetLastError());
                return;
            }

            DCB dcbSerialParams;
            ZeroMemory(&dcbSerialParams, DCB.sizeof);
            dcbSerialParams.DCBlength = DCB.sizeof;
            if (!GetCommState(hCom, &dcbSerialParams))
			{
                CloseHandle(hCom);
                hCom = INVALID_HANDLE_VALUE;

                writeln("GetCommState failed with error %d.\n", GetLastError());
                return;
            }

            dcbSerialParams.BaudRate = DWORD(params.baudRate);
            dcbSerialParams.ByteSize = 8;
            dcbSerialParams.StopBits = ONESTOPBIT;
            dcbSerialParams.Parity = NOPARITY;

            if (!SetCommState(hCom, &dcbSerialParams))
			{
                CloseHandle(hCom);
                hCom = INVALID_HANDLE_VALUE;

                writeln("Error to Setting DCB Structure.\n");
                return;
            }

            COMMTIMEOUTS timeouts = {};
            timeouts.ReadIntervalTimeout = 50;
            timeouts.ReadTotalTimeoutConstant = 50;
            timeouts.ReadTotalTimeoutMultiplier = 10;
            timeouts.WriteTotalTimeoutConstant = 50;
            timeouts.WriteTotalTimeoutMultiplier = 10;
            if (!SetCommTimeouts(hCom, &timeouts))
			{
                CloseHandle(hCom);
                hCom = INVALID_HANDLE_VALUE;

                writeln("Error to Setting Time outs.\n");
                return;
            }

            writeln(format("Opened %s: 0x%x", device, hCom));
        }

        void close()
		{
            CloseHandle(hCom);
        }

        ptrdiff_t read(void[] buffer)
		{
            DWORD bytesRead;
            if (ReadFile(hCom, buffer.ptr, cast(DWORD)buffer.length, &bytesRead, null))
			{
                return bytesRead;
            }
			else
			{
                // Handle error
                return -1;
            }
        }

        ptrdiff_t write(const(void[]) buffer)
		{
            DWORD bytesWritten;
            if (WriteFile(hCom, buffer.ptr, cast(DWORD)buffer.length, &bytesWritten, null))
			{
                return bytesWritten;
            }
			else
			{
                // Handle error
                return -1;
            }
        }
    }
}
else version(Posix)
{
    import core.sys.posix.termios;
    import core.sys.posix.unistd;
    import core.sys.posix.fcntl;
    import core.stdc.stdint : ptrdiff_t;
    import std.string : toStringz;

    struct SerialPort
	{
        int fd = -1;

        void open(string device, ref in SerialParams params = SerialParams())
		{
            fd = core.sys.posix.fcntl.open(device.toStringz(), O_RDWR | O_NOCTTY | O_NDELAY);
            if (fd == -1)
			{
                writeln("Failed to open device %s.\n", params.device);
            }

            termios tty;
            tcgetattr(fd, &tty);

            cfsetospeed(&tty, params.baudRate);
            cfsetispeed(&tty, params.baudRate);

            tty.c_cflag &= ~PARENB; // Clear parity bit
            tty.c_cflag &= ~CSTOPB; // Clear stop field
            tty.c_cflag &= ~CSIZE;  // Clear size bits
            tty.c_cflag |= CS8;     // 8 bits per byte
            tty.c_cflag &= ~CRTSCTS;// Disable RTS/CTS hardware flow control
            tty.c_cflag |= CREAD | CLOCAL; // Turn on READ & ignore ctrl lines

            tty.c_lflag &= ~ICANON;
            tty.c_lflag &= ~ECHO;   // Disable echo
            tty.c_lflag &= ~ECHOE;  // Disable erasure
            tty.c_lflag &= ~ECHONL; // Disable new-line echo
            tty.c_lflag &= ~ISIG;   // Disable interpretation of INTR, QUIT and SUSP
            tty.c_iflag &= ~(IXON | IXOFF | IXANY); // Turn off s/w flow ctrl
            tty.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL); // Disable any special handling of received bytes

            tty.c_oflag &= ~OPOST; // Prevent special interpretation of output bytes (e.g. newline chars)
            tty.c_oflag &= ~ONLCR; // Prevent conversion of newline to carriage return/line feed

            tty.c_cc[VTIME] = 1;    // Wait for up to 1 deciseconds, return as soon as any data is received
            tty.c_cc[VMIN] = 0;

            if (tcsetattr(fd, TCSANOW, &tty) != 0)
			{
                // Handle error
            }
        }

        void close()
		{
            close(fd);
        }

        ptrdiff_t read(void[] buffer)
		{
            ssize_t bytesRead = read(fd, buffer.ptr, buffer.length);
            return bytesRead;
        }

        ptrdiff_t write(const(void[]) buffer)
		{
            ssize_t bytesWritten = write(fd, buffer.ptr, buffer.length);
            return bytesWritten;
        }
    }
}
else
{
    static assert(false, "No serial implementation!");
}
