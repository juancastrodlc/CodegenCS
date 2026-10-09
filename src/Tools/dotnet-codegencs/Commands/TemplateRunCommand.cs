using System;
using System.CommandLine;
using System.CommandLine.Parsing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Console = InterpolatedColorConsole.ColoredConsole;
using static InterpolatedColorConsole.Symbols;
using DependencyContainer = CodegenCS.Utils.DependencyContainer;
using System.Reflection;
using CodegenCS.Runtime;
using ExecutionContext = CodegenCS.Runtime.ExecutionContext;
using System.Collections.Generic;

namespace CodegenCS.DotNetTool.Commands
{
    internal class TemplateRunCommand
    {
        internal readonly Argument<string> _templateArg;
        internal readonly Argument<string[]> _modelsArg;
        internal readonly Argument<string[]> _templateSpecificArguments;
        internal readonly Option<string[]> _referencesArg;
        private readonly Option<string> _outputFolderOption = LegacyCommandLineExtensions.CreateOption<string>(new[] { "--OutputFolder", "-o" }, "Folder to save output [default: current folder]", ArgumentArity.ZeroOrOne, "OutputFolder");
        private readonly Option<string> _fileOption = LegacyCommandLineExtensions.CreateOption<string>(new[] { "--File", "-f" }, "Default Output File [default: \"{MyTemplate}.g.cs\"]", ArgumentArity.ZeroOrOne, "DefaultOutputFile");

        internal bool _verboseMode = false;
        private bool _showTemplateHelp = false;
        private int _modelsParsedForTemplateArgs;
        private readonly ILogger _logger;
        private FileInfo _templateFile = null;
        private FileInfo _originallyInvokedTemplateFile;
        internal TemplateLauncher.TemplateLauncher _launcher = null;
        private CodegenContext _ctx = new CodegenContext(); // _ctx = new DotNet.DotNetCodegenContext(); if user passes csproj file, etc.
        internal int? _expectedModels = null;
        internal int? _initialParsedModels = null;
        internal Command _command;
        internal CliCommandParser _cliCommandParser;
        internal int? buildResult = null;
        internal int? loadResult = null;
        DependencyContainer _dependencyContainer;


        public TemplateRunCommand(Command fakeTemplateCommand = null)
        {
            _templateArg = new Argument<string>("template") { Description = "Template to run. E.g. \"MyTemplate.dll\" or \"MyTemplate.cs\" or \"MyTemplate\"", Arity = ArgumentArity.ExactlyOne };
            _modelsArg = new Argument<string[]>("models")
            {
                Description = "Input Model(s) E.g. \"DbSchema.json\", \"ApiEndpoints.yaml\", etc. Templates might expect 0, 1 or 2 models",
                CustomParser = ParseModels,
                //Arity = new ArgumentArity(0, 2)
                // If we have limited arity (e.g. 0 to 2 args) using OnlyTake() when parsing this argument (Models) won't work:
                // even if we OnlyTake(1) the next argument (TemplateArgs parsed by ParseTemplateArgs()) will still miss one token (ParseResultVisitor misses the PassedOver arguments)

                // So we have to be unlimited:
                Arity = ArgumentArity.ZeroOrMore
            };
            _templateSpecificArguments = new Argument<string[]>("TemplateArgs")
            {
                CustomParser = ParseTemplateArgs,
                Description = "Template-specific arguments/options (if template requires/accepts it)",
                Arity = new ArgumentArity(0, 999), 
                //Arity = ArgumentArity.ZeroOrMore,
                HelpName ="template_args"
            };

            _referencesArg = LegacyCommandLineExtensions.CreateOption<string[]>(
                new[] { "--reference", "-r" },
                """
                Add dll references
                Can use full path or relative path.
                Relative paths will first search relative to current location,
                and if not found will look relative to dotnet core libraries location
                (e.g. C:\Program Files\dotnet\shared\Microsoft.NETCore.App\8.0.5)
                Examples: -r:System.Xml.dll
                Examples: -r:\"C:\Program Files\dotnet\shared\Microsoft.NETCore.App\8.0.5\System.Xml.dll\"
                """,
                ArgumentArity.ZeroOrMore,
                "dll_reference");
            _referencesArg.CustomParser = ParseAssemblyReferences;

            _logger = new ColoredConsoleLogger();
            
            if (fakeTemplateCommand == null)
                _command = GetCommand();
            else
            {
                _command = GetFakeRunCommand();
                _command.Add(fakeTemplateCommand);
            }
            _dependencyContainer = new DependencyContainer().AddConsole();
        }

        public Command GetCommand(string commandName = "run")
        {
            var command = new Command(commandName);

            AddGlobalOptions(command);

            command.Add(_templateArg);

            command.Add(_modelsArg);

            command.Add(_templateSpecificArguments);

            command.Add(_referencesArg);

            command.SetAction(HandleCommand);

            return command;
        }
        protected void AddGlobalOptions(Command command)
        {
            command.AddGlobalOption(_outputFolderOption);
            command.AddGlobalOption(_fileOption);
        }
        protected internal Command GetFakeRunCommand()
        {
            var command = new Command("run");
            AddGlobalOptions(command);
            return command;
        }

        string[] ParseModels(ArgumentResult result)
        {
            string[] models = new string[_expectedModels ?? 2];
            int foundModels = 0;
            int maxModels = Math.Min(Math.Min(result.Tokens.Count, 2), _expectedModels ?? 2);
            for (int i = 0; i < maxModels; i++)
            {
                FileInfo fi;
                if ((fi = new FileInfo(result.Tokens[i].Value)).Exists || (fi = new FileInfo(result.Tokens[i].Value + ".json")).Exists || (fi = new FileInfo(result.Tokens[i].Value + ".yaml")).Exists)
                {
                    foundModels++;
                    models[i] = fi.FullName;
                }
                else if (_expectedModels != null) // if we already know the number of expected models we can be strict, else we should be lenient and ignore non-models
                {
                    result.AddError("ERROR: Cannot find model: " + result.Tokens[i].Value);
                    return null;
                }
            }
            _initialParsedModels ??= foundModels;
            _modelsParsedForTemplateArgs = foundModels;
            if (_verboseMode)
                Console.WriteLine(ConsoleColor.DarkGray, "[DEBUG] Models: " + (models.ToList().Take(foundModels).Any() ? String.Join(", ", models.ToList().Take(foundModels)) : "<none>"));
            if (result.Tokens.Count != foundModels)
                result.OnlyTake(foundModels);
            if (foundModels == models.Length)
                return models;
            return models.ToList().Take(foundModels).ToArray();
        }

        string[] ParseTemplateArgs(ArgumentResult result)
        {
            // Since Models arg is unlimited (ArgumentArity.ZeroOrMore) this subsequent argument will get the same arguments, and we have to skip the number of tokens which were matched to models
            int models = _modelsParsedForTemplateArgs;
            var arr = result.Tokens.Select(t => t.Value).ToArray();
            if (_verboseMode && arr.Any())
                Console.WriteLine(ConsoleColor.DarkGray, $"[DEBUG] TemplateArgs: {ConsoleColor.Yellow}'{String.Join("', '", arr)}'{PREVIOUS_COLOR}");
            else
                Console.WriteLine(ConsoleColor.DarkGray, $"[DEBUG] TemplateArgs: <none>");
            return arr;
        }
        string[] ParseAssemblyReferences(ArgumentResult result)
        {
            var references = result.Tokens.Select(t => t.Value).ToArray();
            if (_verboseMode)
                Console.WriteLine(ConsoleColor.DarkGray, $"[DEBUG] AssemblyReferences: {ConsoleColor.Yellow}'{String.Join("', '", references)}'{PREVIOUS_COLOR}");
            return references;
        }


        /// <summary>
        /// If template is not yet built (DLL), builds CS or CSX into a DLL
        /// </summary>
        public async Task<int> BuildScriptAsync(string template, string[] references)
        {
            string currentCommand = "dotnet-codegencs template run";
            using (var consoleContext = Console.WithColor(ConsoleColor.Cyan))
            {
                System.Console.CancelKeyPress += (s, e) =>
                {
                    Console.WriteLineError(ConsoleColor.Red, $"Stopping {ConsoleColor.Yellow}'{currentCommand}'{PREVIOUS_COLOR}...");
                    consoleContext.RestorePreviousColor();
                    //Environment.Exit(-1); CancelKeyPress will do it automatically since we didn't set e.Cancel to true
                };
            }

            string[] validExtensions = new string[] { ".dll", ".cs", ".csx" };
            _templateFile = File.Exists(template) ? new FileInfo(template) : null;
            for (int i = 0; _templateFile == null && i < validExtensions.Length; i++)
            {
                if (File.Exists(template + validExtensions[i]))
                    _templateFile = new FileInfo(template + validExtensions[i]);
            }

            if (_templateFile == null)
            {
                if (validExtensions.Contains(Path.GetExtension(template).ToLower()))
                    Console.WriteLineError(ConsoleColor.Red, $"Cannot find Template {ConsoleColor.Yellow}'{template}'{PREVIOUS_COLOR}");
                else
                    Console.WriteLineError(ConsoleColor.Red, $"Cannot find Template {ConsoleColor.Yellow}'{template}.dll'{PREVIOUS_COLOR} or {ConsoleColor.Yellow}'{template}.cs'{PREVIOUS_COLOR} or {ConsoleColor.Yellow}'{template}.csx'{PREVIOUS_COLOR}");
                return -1;
            }
            else if (!validExtensions.Contains(Path.GetExtension(_templateFile.FullName).ToLower()))
            {
                Console.WriteLineError(ConsoleColor.Red, $"Invalid Template name {ConsoleColor.Yellow}'{_templateFile.Name}'{PREVIOUS_COLOR}");
                Console.WriteLineError(ConsoleColor.Red, $"Valid template extensions are {ConsoleColor.Yellow}{string.Join(", ", validExtensions.Select(ext => ext.TrimStart('.')))}{PREVIOUS_COLOR}");
                return -1;
            }

            // If user provided a single CS/CSX file (instead of a DLL file) first we need to build into a dll
            if (Path.GetExtension(_templateFile.Name).ToLower() != ".dll")
            {
                currentCommand = "dotnet-codegencs template build";
                string tmpFolder = Path.Combine(Path.GetTempPath() ?? Directory.GetCurrentDirectory(), Guid.NewGuid().ToString());
                var builderArgs = new TemplateBuilder.TemplateBuilder.TemplateBuilderArgs()
                {
                    Template = new string[] { _templateFile.FullName },
                    //TODO define folder+filename by hash of template name+contents, to cache results.
                    Output = Path.Combine(tmpFolder, Path.GetFileNameWithoutExtension(_templateFile.FullName)) + ".dll",
                    VerboseMode = _verboseMode,
                    ExtraReferences = references.ToList(),
                };
                var builder = new TemplateBuilder.TemplateBuilder(_logger, builderArgs);

                var builderResult = await builder.ExecuteAsync();

                if (builderResult.ReturnCode != 0)
                {
                    Console.WriteLineError(ConsoleColor.Red, $"TemplateBuilder ({ConsoleColor.Yellow}'{currentCommand}'{PREVIOUS_COLOR}) Failed.");
                    return -1;
                }
                currentCommand = "dotnet-codegencs template run";
                _originallyInvokedTemplateFile = _templateFile;
                _templateFile = new FileInfo(builderArgs.Output);
            }

            var currentDirectory = Directory.GetCurrentDirectory();
            var templatePath = (_originallyInvokedTemplateFile ?? _templateFile).FullName;
            var executionContext = new ExecutionContext(templatePath, currentDirectory);
            _dependencyContainer.RegisterSingleton<ExecutionContext>(() => executionContext);
            var searchPaths = new string[] { new FileInfo(executionContext.TemplatePath).Directory.FullName, currentDirectory };
            _dependencyContainer.AddModelFactory(searchPaths);

            return 0;
        }

        public async Task<int> LoadTemplateAsync(int? providedModels)
        {
            _launcher ??= new TemplateLauncher.TemplateLauncher(_logger, _ctx, _dependencyContainer, _verboseMode) { _originallyInvokedTemplateFile = _originallyInvokedTemplateFile };
            var loadResult = await _launcher.LoadAsync(_templateFile.FullName, providedModels);
            _expectedModels = (loadResult.Model1Type != null ? 1 : 0) + (loadResult.Model2Type != null ? 1 : 0);
            return loadResult.ReturnCode;
        }

        protected async Task<int> HandleCommand(ParseResult parseResult)
        {
            var template = parseResult.GetValue(_templateArg);
            var references = parseResult.GetValue(_referencesArg);
            _verboseMode |= parseResult.GetValue(CliCommandParser.VerboseOption);
            _showTemplateHelp |= parseResult.GetValue(CliCommandParser.HelpOption);

            string currentCommand = "dotnet-codegencs template run";
            int statusCode;
            using (var consoleContext = Console.WithColor(ConsoleColor.Cyan))
            {
                System.Console.CancelKeyPress += (s, e) =>
                {
                    Console.WriteLineError(ConsoleColor.Red, $"Stopping {ConsoleColor.Yellow}'{currentCommand}'{PREVIOUS_COLOR}...");
                    consoleContext.RestorePreviousColor();
                    //Environment.Exit(-1); CancelKeyPress will do it automatically since we didn't set e.Cancel to true
                };


                var buildResult = await BuildScriptAsync(template, references);
                if (buildResult != 0)
                {
                    Console.WriteLineError(ConsoleColor.Red, "ERROR: Could not load or build template: " + template);
                    return 1;
                }

                var loadResult = await LoadTemplateAsync(_initialParsedModels);
                if (loadResult != 0)
                {
                    Console.WriteLineError(ConsoleColor.Red, "ERROR: Could not load template: " + template);
                    return 1;
                }

                if (_expectedModels != _initialParsedModels)
                {
                    var args = parseResult.Tokens.Select(token => token.Value).ToArray();
                    parseResult = parseResult.RootCommandResult.Command.Parse(
                        args, new ParserConfiguration { EnablePosixBundling = false });
                }

                _ = parseResult.GetValue(_templateSpecificArguments);

                _launcher.ParseCliUsingCustomCommand = ParseCliUsingCustomCommand;
                _launcher.ShowTemplateHelp = _showTemplateHelp;

                var cliArgs = new CommandArgs
                {
                    Template = parseResult.GetValue(_templateArg),
                    Models = parseResult.GetValue(_modelsArg),
                    OutputFolder = parseResult.GetValue(_outputFolderOption),
                    File = parseResult.GetValue(_fileOption),
                    TemplateArgs = parseResult.GetValue(_templateSpecificArguments)
                };

                // now we have the DLL to run...
                var launcherArgs = new TemplateLauncher.TemplateLauncher.TemplateLauncherArgs()
                {
                    Template = _templateFile.FullName,
                    Models = cliArgs.Models,
                    OutputFolder = cliArgs.OutputFolder,
                    ExecutionFolder = Directory.GetCurrentDirectory(),
                    DefaultOutputFile = cliArgs.File,
                    TemplateSpecificArguments = cliArgs.TemplateArgs,
                    //TODO: do we have to pass third-party (non-framework) references here so they can be loaded?
                };

                statusCode = await _launcher.ExecuteAsync(launcherArgs, parseResult);

                if (statusCode != 0)
                {
                    if (statusCode != -2) // invalid template args has already shown the help page
                        Console.WriteLineError(ConsoleColor.Red, $"TemplateLauncher ({ConsoleColor.Yellow}'{currentCommand}'{PREVIOUS_COLOR}) Failed.");
                    return -1;
                }

                return 0;
            }
        }

        /// <summary>
        /// Creates a custom Command for the template, configures it (using ConfigureCommand() defined in template)
        /// </summary>
        Command CreateCustomCommand(string filePath, Type model1Type, Type model2Type, MethodInfo configureCommand)
        {
            // Create a subcommand for the invoked template, add model arguments, add custom options/arguments
            var customTemplateCommand = new Command(filePath.Replace(" ", "_"));

            if (model1Type != null && model2Type != null)
            {
                customTemplateCommand.Add(new Argument<string>("Model1") { Description = $"Model of type {model1Type.FullName}", Arity = ArgumentArity.ExactlyOne });
                customTemplateCommand.Add(new Argument<string>("Model2") { Description = $"Model of type {model2Type.FullName}", Arity = ArgumentArity.ExactlyOne });
            }
            else if (model1Type != null)
            {
                customTemplateCommand.Add(new Argument<string>("Model") { Description = $"Model of type {model1Type.FullName}", Arity = ArgumentArity.ExactlyOne });
            }

            //configure custom options/arguments
            configureCommand.Invoke(null, new object[] { customTemplateCommand });

            return customTemplateCommand;
        }

        public ParseResult ParseCliUsingCustomCommand(string filePath, Type model1Type, Type model2Type, DependencyContainer dependencyContainer, MethodInfo configureCommand, ParseResult parseResult)
        {
            // If template have a static ConfigureCommand(Command), let's create a fake command and reparse the command-line arguments using the arguments/options defined in ConfigureCommand()

            // This dummy (temporary) command is just to parse (validate) the Arguments/Options defined in "public static void ConfigureCommand(Command)"
            var templateCommand = CreateCustomCommand(filePath, model1Type, model2Type, configureCommand);
            dependencyContainer.RegisterSingleton<Command>(templateCommand);

            // Command is registered under a new (fake) RootCommand structure which has fake "template run" (with a single subcommand specific for running this command)
            var fakeRootCommand = new CliCommandParser(new TemplateRunCommand(templateCommand)).RootCommand;

            // Parse again from root, but now with fake run command
            var allArgs = parseResult.Tokens.Select(t => t.Value).ToList();
            var templateArg = parseResult.GetValue(_templateArg);
            int templatePos = allArgs.IndexOf(templateArg);
            if (templatePos > 0)
                allArgs[templatePos] = filePath;

            parseResult = fakeRootCommand.Parse(allArgs, new ParserConfiguration { EnablePosixBundling = false });

            return parseResult;
        }

        protected class CommandArgs
        {
            /// <see cref="TemplateLauncher.TemplateLauncher.TemplateLauncherArgs.Template"/>
            public string Template { get; set; }

            /// <see cref="TemplateLauncher.TemplateLauncher.TemplateLauncherArgs.Models"/>
            public string[] Models { get; set; }

            /// <see cref="TemplateLauncher.TemplateLauncher.TemplateLauncherArgs.OutputFolder"/>
            public string OutputFolder { get; set; }


            /// <see cref="TemplateLauncher.TemplateLauncher.TemplateLauncherArgs.DefaultOutputFile"/>
            public string File { get; set; }

            public string[] TemplateArgs { get; set; }

        }

    }
}
