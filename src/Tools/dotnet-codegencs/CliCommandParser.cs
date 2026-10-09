using System.CommandLine;
using System.CommandLine.Parsing;
using System.Linq;

namespace CodegenCS.DotNetTool
{
    internal class CliCommandParser
    {
        private readonly ParserConfiguration _parserConfiguration = new ParserConfiguration
        {
            EnablePosixBundling = false
        };
        private readonly Parser _parser;

        internal readonly Command RootCommand = new RootCommand();
        internal Parser Parser => _parser;

        private readonly Command _templateCommands = new Command("template");
        internal readonly Commands.TemplateRunCommand _runTemplateCommandWrapper;
        internal Command _runTemplateCommand => _runTemplateCommandWrapper._command;

        private readonly Command _buildTemplateCommand = Commands.TemplateBuildCommand.GetCommand();
        private readonly Command _cloneTemplateCommand = Commands.TemplateCloneCommand.GetCommand();

        private readonly Command _modelCommands = new Command("model");
        private readonly Command _modelDbSchemaCommands = new Command("dbschema");
        internal readonly Command _modelDbSchemaExtractCommand = Models.DbSchema.Extractor.CliCommand.GetCommand();

        internal static readonly Option<bool> HelpOption = LegacyCommandLineExtensions.CreateOption<bool>(
            new[] { "--help", "-?", "/?", "/help", "--?" }, "\nShow Help");
        internal static readonly Option<bool> VerboseOption = LegacyCommandLineExtensions.CreateOption<bool>(
            new[] { "--verbose", "--debug" }, "Verbose mode");

        internal CliCommandParser()
            : this(new Commands.TemplateRunCommand())
        {
        }

        internal CliCommandParser(Commands.TemplateRunCommand runTemplateCommandWrapper)
        {
            _runTemplateCommandWrapper = runTemplateCommandWrapper;
            _runTemplateCommandWrapper._cliCommandParser = this;
            _parser = new Parser(RootCommand);
            ConfigureCommandLine();
        }

        private void ConfigureCommandLine()
        {
            RootCommand.Add(_templateCommands);
            _templateCommands.Add(_runTemplateCommand);
            _templateCommands.Add(_buildTemplateCommand);
            _templateCommands.Add(_cloneTemplateCommand);

            _modelDbSchemaCommands.Add(_modelDbSchemaExtractCommand);
            _modelCommands.Add(_modelDbSchemaCommands);
            RootCommand.Add(_modelCommands);

            HelpOption.Recursive = true;
            VerboseOption.Recursive = true;
            RootCommand.Add(HelpOption);
            RootCommand.Add(VerboseOption);

            RootCommand.SetAction(parseResult => ShowHelp(parseResult));
            _templateCommands.SetAction(parseResult => ShowHelp(parseResult));
            _modelCommands.SetAction(parseResult => ShowHelp(parseResult));
            _modelDbSchemaCommands.SetAction(parseResult => ShowHelp(parseResult));
        }

        internal ParseResult Parse(string[] args) => CommandLineParser.Parse(RootCommand, args, _parserConfiguration);

        internal ParseResult Parse(System.Collections.Generic.IReadOnlyList<string> args) =>
            CommandLineParser.Parse(RootCommand, args, _parserConfiguration);

        private int ShowHelp(ParseResult parseResult)
        {
            var helpResult = CommandLineParser.Parse(parseResult.CommandResult.Command, "--help", _parserConfiguration);
            return helpResult.Invoke();
        }
    }
}
