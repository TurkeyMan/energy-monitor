module manager.console.console;

import urt.array;
import urt.map;
import urt.mem;
import urt.string;
import urt.string.format;
import urt.util;

import manager.console.builtin_commands;
import manager.console.command;
import manager.console.expression;
import manager.console.function_command;
import manager.console.session;
import manager.instance;


/// Find a console instance by name.
/// \param identifier
///  Name of the console instance to find.
/// \returns Pointer to the console instance, or `nullptr` if no console with that name exists.
Console* FindConsole(const(char)[] identifier) nothrow @nogc
{
    Console* instance = s_consoleInstances;
    while (instance && instance.m_identifier != identifier[])
        instance = instance.m_nextConsoleInstance;
    return instance;
}


struct Console
{
nothrow @nogc:

    ApplicationInstance appInstance;

    Scope root;
//    Command[] commands;

    this() @disable;

    this(ApplicationInstance appInstance, String identifier, NoGCAllocator allocator, NoGCAllocator tempAllocator = null)
    {
        this.appInstance = appInstance;
        m_allocator = allocator;
        m_tempAllocator = tempAllocator ? tempAllocator : allocator;
        m_identifier = identifier;

        // add the console instance to the registry
        // TODO: this is not threadsafe! creating/destroying console instances should be threadsafe!
        assert(FindConsole(identifier) is null, tconcat("Console '", identifier[], "' already exists!"));
        m_nextConsoleInstance = s_consoleInstances;
        s_consoleInstances = &this;

        root = m_allocator.allocT!Scope(this, String(null));
        RegisterBuiltinCommands(this);
    }

    ~this()
    {
        assert(false);
//        for (dcConsoleSession* session : m_sessions)
//            m_allocator.Delete(session);
//
//        for (auto&& pair : m_commands)
//            m_allocator.Delete(pair.val);
//
//        dcDebugConsole* list = s_consoleInstances;
//        if (list == this)
//            s_consoleInstances = m_nextConsoleInstance;
//        else
//        {
//            while (list->m_nextConsoleInstance && list->m_nextConsoleInstance != this)
//                list = list->m_nextConsoleInstance;
//            BC_ASSERT(list != nullptr, "Console instance was not in the registry somehow?");
//            // m_nextConsoleInstance is 'this'; remove it from the list
//            list->m_nextConsoleInstance = list->m_nextConsoleInstance->m_nextConsoleInstance;
//        }
    }

    Scope getRoot() nothrow @nogc
    {
        return root;
    }

    /// Update the console instance. This will update all attached sessions.
    void update()
    {
        foreach (session; m_sessions)
        {
            if (session.isAttached)
                session.update();
//            if (!session.IsAttached)
//                m_sessions.Erase(*it);
        }
    }

    /// Get the console's identifier
    const(char)[] identifier() { return m_identifier; }

    /// Get the console's prompt string
    const(char)[] getPrompt() nothrow @nogc { return m_prompt; }

    /// Set the prompt that text-based sessions will show when accepting commands.
    String setPrompt(String prompt)
    {
        return m_prompt.swap(prompt);
    }

    /// Create a new session instance of the type `SessionType` (derived from Session) bound to this console instance.
    /// \param args
    ///  Constructor args forwarded to `SessionType`'s constructor.
    /// \returns A pointer to the new session instance.
    SessionType createSession(SessionType, Args...)(auto ref Args args)
        if (is(SessionType : Session))
        {
            SessionType session = m_allocator.allocT!SessionType(this, forward!args);
            session.setPrompt(m_prompt);
            m_sessions ~= session;
            return session;
        }

    void destroySession(Session session)
    {
        assert(session.m_console is &this, "Session does not belong to this console instance.");

        m_sessions.removeFirstSwapLast(session);
        m_allocator.freeT(session);
    }

    // TODO: don't like this API, it should be a method of Session...
    CommandState execute(Session session, const(char)[] cmdLine)
    {
        assert(session._currentCommand is null, "TODO: gotta do something about concurrent command execution...");

        Scope s = session.curScope;

        cmdLine = cmdLine.trimCmdLine;
        if (cmdLine.empty)
            return null;

        if (cmdLine.frontIs('/'))
            s = getRoot();
        return s.execute(session, cmdLine);
    }


    /// Request auto-completion for the given incomplete command line string.
    /// \param cmdLine
    ///  A command line string to attempt completion.
    /// \returns A new command line with the attempted auto-completion applied. If no completion was applicable, the result is `cmdLine` as given.
    String complete(String cmdLine) const
    {
        assert(false);
//        bcStringView args = cmdLine;
//        bcStringView command = dcTakeFirstToken(args);
//
//        // if we're trying to complete a command name
//        if (command.IsEmpty() || (args.IsEmpty() && !dcIsSeparator(cmdLine[cmdLine.Size() - 1])))
//        {
//            bcVector<bcString> tokens = Suggest(command);
//            if (!tokens.IsEmpty())
//                cmdLine.Append(dcGetCompletionSuffix(command, tokens));
//            return cmdLine;
//        }
//
//        // see if we can find the command
//        auto it = m_commands.Find(dcToLower(bcString{ m_tempAllocator, command }));
//        if (it == nullptr)
//            return cmdLine;
//
//        bcString result{ m_allocator, command };
//        result.AppendMultiToString(' ', it->val->Complete(bcString{ m_tempAllocator, args }));
//        return result;
        return String();
    }

    /// Suggest a list of completion terms for the current incomplete command line.
    /// If a command line tail does not end on whitespace, the tail is taken to be a partially typed arguments, and filters the possible arguments by the partial prefix.
    /// \param cmdLine
    ///  A command line string to analyse for auto-complete suggestions.
    /// \returns A filtered list of possible completion terms.
    String[] suggest(const(char)[] cmdLine) const
    {
        assert(false);
//        bcStringView args = cmdLine;
//        bcStringView command = dcTakeFirstToken(args);
//
//        if (command.IsEmpty() || (args.IsEmpty() && !dcIsSeparator(cmdLine[cmdLine.Size() - 1])))
//        {
//            if (command.IsEmpty())
//            {
//                bcVector<bcString> commands{ m_allocator };
//                for (auto&& pair : m_commands)
//                    commands.PushBack(pair.key);
//                return commands;
//            }
//
//            // gather commands
//            bcVector<bcStringView> commands{ m_tempAllocator };
//            for (auto&& pair : m_commands)
//                commands.PushBack(pair.key);
//
//            // filter for partially typed command
//            dcFilterTokens(commands, dcToLower(bcString{ m_tempAllocator, command }));
//
//            bcVector<bcString> filteredCommands{ m_allocator };
//            for (bcStringView cmd : commands)
//                filteredCommands.PushBack(bcString{ m_allocator, cmd });
//            return filteredCommands;
//        }
//
//        // see if we can find the command
//        auto it = m_commands.Find(dcToLower(bcString{ m_tempAllocator, command }));
//        if (it == nullptr)
//            return bcVector<bcString>(m_allocator);
//
//        // request suggestions from the command
//        return it->val->Suggest(args);
        return null;
    }

    void registerCommand(const(char)[] _scope, Command command)
    {
        Scope s = createScope(_scope);
        s.addCommand(command);
    }

    void registerCommands(const(char)[] _scope, Command[] commands)
    {
        Scope s = createScope(_scope);
        foreach (cmd; commands)
            s.addCommand(cmd);
    }

    void registerCommand(alias method, Instance)(const(char)[] _scope, Instance instance, const(char)[] commandName = null)
    {
        // TODO: put this back in to tell users how to get the signature right!
//        alias Fun = typeof(method)*;
//        static assert(is(Fun : R function(Session, A) nothrow @nogc, R, A...), typeof(method).stringof ~ " must be nothrow @nogc!");

        return registerCommand(_scope, FunctionCommand.create!method(this, instance, commandName));
    }


    void unregisterCommand(const(char)[] _scope, const(char)[] command)
    {
        Scope s = cast(Scope)findCommand(_scope);
        assert(s !is null, tconcat("No scope: ", _scope));

        assert(false);
        // TODO
    }

    void unregisterCommands(const(char)[] _scope, const(char)[][] commands)
    {
        Scope s = cast(Scope)findCommand(_scope);
        assert(s !is null, tconcat("No scope: ", _scope));

        foreach (cmd; commands)
        {
            assert(false);
            // TODO
        }
    }




    void addCommand(Command command, Scope parent)
    {
        parent.addCommand(command);
    }

    Command findCommand(const(char)[] cmdPath)
    {
        Scope s = getRoot();
        Command cmd = null;

        if (cmdPath.frontIs('/'))
        {
            cmdPath = cmdPath[1..$];
            s = getRoot();
        }

        while (!cmdPath.empty)
        {
            if (s is null)
                return null;

            if (cmdPath.frontIs(".."))
            {
                s = s.parent;
                cmd = s;
                if (cmdPath.length == 2)
                    return cmd;
                else if (cmdPath[2] != '/')
                    return null;
                cmdPath = cmdPath[3..$];
            }
            else
            {
                const(char)[] identifier = cmdPath.takeIdentifier;
                if (identifier.empty)
                    return null;
                cmd = s.getCommand(identifier);
                if (!cmd)
                    return null;
                if (cmdPath.empty)
                    break;
                if (cmdPath[0] != '/')
                    return null;
                cmdPath = cmdPath[1..$];
                s = cast(Scope)cmd;
            }
        }
        return cmd;
    }

    Scope createScope(const(char)[] path)
    {
        assert(path.frontIs('/'), "Scope path must be root relative, ie: /path/to/scope");
        path = path[1..$];

        Scope s = getRoot();

        while (!path.empty)
        {
            // check for child
            const(char)[] identifier = path.takeIdentifier;
            assert(!identifier.empty, "Invalid scope idenitifier");

            Command cmd = s.getCommand(identifier);
            if (!cmd)
            {
                import urt.mem.string : addString;
                Scope newScope = m_allocator.allocT!Scope(this, String(identifier.addString));
                s.addCommand(newScope);
                s = newScope;
            }
            else
            {
                s = cast(Scope)cmd;
                assert(s !is null, "Command already exists, is not a Scope.");
            }

            if (!path.empty)
            {
                assert(path[0] == '/', "Expected Scope separator");
                assert(path.length > 1, "Expected Scope identifier");
                path = path[1..$];
            }
        }

        return s;
    }

package:
    NoGCAllocator m_allocator;
    NoGCAllocator m_tempAllocator;

    String m_identifier;
    String m_prompt;

    Map!(String, Command) m_commands;
//    HashSet<dcConsoleSession*> m_sessions;
    Array!Session m_sessions;

    Console* m_nextConsoleInstance = null;
}


private:

__gshared Console* s_consoleInstances = null;
