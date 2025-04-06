module manager.log;

import urt.array;
import urt.log;
import urt.string;
import urt.variant;

import manager.console;
import manager.console.command;
import manager.console.session;
import manager.plugin;

enum Category
{
	Info,
	Warning,
	Error,
	Alert,
	Debug
}

class LogModule : Module
{
    mixin DeclareModule!"log";
nothrow @nogc

    override void init()
    {
        Command[5] commands = [
            app.allocator.allocT!LogCommand(app.console, "info", Category.Info, this),
            app.allocator.allocT!LogCommand(app.console, "warn", Category.Warning, this),
            app.allocator.allocT!LogCommand(app.console, "error", Category.Error, this),
            app.allocator.allocT!LogCommand(app.console, "alert", Category.Alert, this),
            app.allocator.allocT!LogCommand(app.console, "debug", Category.Debug, this)
        ];

        app.console.registerCommands("/log", commands);
    }
}


private:

class LogCommand : Command
{
nothrow @nogc:

	LogModule instance;
	Category category;

	this(ref Console console, const(char)[] name, Category category, LogModule instance)
	{
		import urt.mem.string;

		super(console, String(name.addString));
		this.instance = instance;
		this.category = category;
	}

    override CommandState execute(Session session, const Variant[] args, const NamedArgument[] namedArgs)
    {
        if (args.length == 0 || args.length > 1)
        {
            session.writeLine("/log command expected string argument");
            return null;
        }

        final switch (category)
        {
            case Category.Info:
                writeInfo(args[0]);
                break;
            case Category.Warning:
                writeWarning(args[0]);
                break;
            case Category.Error:
                writeError(args[0]);
                break;
            case Category.Alert:
                // TODO: implement ALERT type...
                writeError(args[0]);
                break;
            case Category.Debug:
                writeDebug(args[0]);
                break;
        }
        return null;
    }

	version (ExcludeAutocomplete) {} else
	{
		override MutableString!0 complete(const(char)[] cmdLine) const
		{
			assert(false);
			return MutableString!0();
		}


		override Array!(MutableString!0) suggest(const(char)[] cmdLine) const
		{
			return Array!(MutableString!0)();
		}
	}

	version (ExcludeHelpText) {} else
	{
		override const(char)[] help(const(char)[] args) const
		{
			assert(false);
			return String(null);
		}
	}
}
