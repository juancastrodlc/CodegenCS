using System;
using System.CommandLine;
using Console = InterpolatedColorConsole.ColoredConsole;

namespace CodegenCS.Models.DbSchema.Extractor
{
    public static class CliCommand
    {
        public static Command GetCommand(string commandName = "extract")
        {
            var command = new Command(commandName);

            var dbTypeArgument = new Argument<ExtractWizard.DbTypeEnum>("dbtype")
            {
                Description = $"Database type ({string.Join("|", Enum.GetNames(typeof(ExtractWizard.DbTypeEnum)))})",
                CustomParser = argResult =>
                {
                    if (Enum.TryParse(argResult.Tokens[0].Value, ignoreCase: true, out ExtractWizard.DbTypeEnum dbType))
                        return dbType;

                    argResult.AddError("Invalid dbtype: " + argResult.Tokens[0].Value);
                    return default;
                },
                Arity = ArgumentArity.ExactlyOne
            };
            command.Add(dbTypeArgument);

            var connectionStringArgument = new Argument<string>("connectionString")
            {
                Description = "Connection String\n" +
                    "MSSQL example: \"Server=MYWORKSTATION\\SQLEXPRESS; Database=AdventureWorks; Integrated Security=True;\"\n" +
                    "MSSQL example: \"Server=MYSERVER; Database=AdventureWorks; User Id=myUsername;******;\"\n" +
                    "PostgreSQL example: \"Host=localhost; Database=Adventureworks; Username=postgres; ******\""
            };
            command.Add(connectionStringArgument);

            var outputArgument = new Argument<string>("output")
            {
                Description = "Output JSON schema. E.g. \"Schema.json\"",
                Arity = ArgumentArity.ExactlyOne
            };
            command.Add(outputArgument);

            command.SetAction(parseResult => HandleCommand(new DbSchemaExtractorArgs
            {
                DbType = parseResult.GetValue(dbTypeArgument),
                ConnectionString = parseResult.GetValue(connectionStringArgument),
                Output = parseResult.GetValue(outputArgument)
            }));

            return command;
        }

        static int HandleCommand(DbSchemaExtractorArgs cliArgs)
        {
            Console.WriteLine(ConsoleColor.Green, $"Executing '{typeof(ExtractWizard).Name}' template...");

            var wizard = new ExtractWizard
            {
                DbType = cliArgs.DbType,
                OutputJsonSchema = cliArgs.Output,
                ConnectionString = cliArgs.ConnectionString
            };

            wizard.Run();

            Console.WriteLine(ConsoleColor.Green, $"Finished executing '{typeof(ExtractWizard).Name}' template.");

            return 0;
        }

        public class DbSchemaExtractorArgs
        {
            public ExtractWizard.DbTypeEnum DbType { get; set; }
            public string ConnectionString { get; set; }
            public string Output { get; set; }
        }
    }
}
