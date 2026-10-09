using System.Collections.Generic;
using System.CommandLine;
using System.CommandLine.Parsing;
using System.Linq;

namespace System.CommandLine
{
    public static class LegacyCommandLineExtensions
    {
        public static Option<T> CreateOption<T>(
            string[] aliases,
            string description = null,
            ArgumentArity? arity = null,
            string helpName = null)
        {
            var option = new Option<T>(aliases[0])
            {
                Description = description,
                HelpName = helpName
            };
            if (arity.HasValue)
                option.Arity = arity.Value;
            foreach (var alias in aliases.Skip(1))
                option.Aliases.Add(alias);
            return option;
        }

        public static void AddArgument(this Command command, Argument argument) => command.Add(argument);

        public static void AddOption(this Command command, Option option) => command.Add(option);

        public static void AddCommand(this Command command, Command childCommand) => command.Add(childCommand);

        public static void AddGlobalOption(this Command command, Option option)
        {
            option.Recursive = true;
            command.Add(option);
        }

        public static T GetValueForArgument<T>(this ParseResult parseResult, Argument<T> argument) =>
            parseResult.GetValue(argument);

        public static T GetValueForOption<T>(this ParseResult parseResult, Option<T> option) =>
            parseResult.GetValue(option);

        public static bool HasOption(this ParseResult parseResult, Option option) =>
            parseResult.GetResult(option) is OptionResult;
    }
}

namespace System.CommandLine.Parsing
{
    public sealed class Parser
    {
        private readonly Command _command;
        private readonly ParserConfiguration _configuration;

        public Parser(Command command)
        {
            _command = command;
            _configuration = new ParserConfiguration { EnablePosixBundling = false };
        }

        public ParseResult Parse(string[] args) => CommandLineParser.Parse(_command, args, _configuration);

        public ParseResult Parse(IReadOnlyList<string> args) => CommandLineParser.Parse(_command, args, _configuration);
    }
}
