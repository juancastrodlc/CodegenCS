using CodegenCS.CodeGenerator;
using CodegenCS.Models.DbSchema;
using Dapper;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.Data.Sqlite;
using Newtonsoft.Json;
using NUnit.Framework;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace CodegenCS.SourceGenerator.Tests
{
    [TestFixture]
    internal class SourceGenerator2Tests
    {
        private static readonly string[] SqliteTypes = { "INTEGER", "TEXT", "REAL", "NUMERIC", "BLOB" };
        private static readonly string[] ExpectedOutput =
        {
            "I'll buy a Tesla Model S (#1, TS-0001) for 79990.00",
            "I'll buy a Mountain Bike (#2, MB-0002) for 1250.50",
        };

        private TestWorkspace _workspace;

        [SetUp]
        public void SetUp() => _workspace = TestWorkspace.FromBaseProject();

        [TearDown]
        public void TearDown() => _workspace.Dispose();

        private DatabaseSchema LoadSchema() =>
            JsonConvert.DeserializeObject<DatabaseSchema>(File.ReadAllText(_workspace.PathOf("AdventureWorksSchema.json")));

        private GeneratorHarness CreateHarness() => new GeneratorHarness()
            .AddSources(_workspace.PathOf("Program.cs"), _workspace.PathOf("IDbConnectionFactory.cs"))
            .AddTemplate(_workspace.PathOf("SimplePOCOGenerator.csx"), "Memory")
            .AddAdditionalFile(_workspace.PathOf("AdventureWorksSchema.json"));

        [Test]
        public void BaseProject_HasNoSqlServerDependencies()
        {
            var csproj = File.ReadAllText(_workspace.PathOf("SourceGenerator2.csproj"));
            var sources = string.Join(Environment.NewLine, Directory.GetFiles(_workspace.Directory, "*.cs").Select(File.ReadAllText));

            Assert.That(csproj, Does.Not.Contain("SqlClient"));
            Assert.That(csproj, Does.Contain("Microsoft.Data.Sqlite"));
            Assert.That(sources, Does.Not.Contain("SqlClient").And.Not.Contain("SqlConnection"));
            Assert.That(sources, Does.Contain("SqliteConnection"));
        }

        [Test]
        public void SchemaJson_DescribesASqliteDatabase()
        {
            var schema = LoadSchema();

            Assert.That(schema.Tables, Is.Not.Empty);
            Assert.That(schema.Tables.Select(t => t.TableSchema).Distinct(), Is.EqualTo(new[] { "main" }));
            Assert.That(schema.Tables.SelectMany(t => t.Columns).Select(c => c.SqlDataType).Distinct(), Is.SubsetOf(SqliteTypes));
            Assert.That(schema.Tables.SelectMany(t => t.ForeignKeys).Select(fk => fk.PKTableSchema).Distinct(), Is.EqualTo(new[] { "main" }));
            Assert.That(schema.Tables.SelectMany(t => t.Indexes).Select(i => i.PhysicalType).Distinct(), Is.EqualTo(new[] { "BTREE" }));
            var defaults = schema.Tables.SelectMany(t => t.Columns).Select(c => c.DefaultSetting).Where(d => d != null).ToList();
            Assert.That(defaults, Has.None.Contains("getdate").And.None.Contains("newid"));
            Assert.That(schema.Tables.SelectMany(t => t.Columns).Select(c => c.ClrType), Has.None.StartsWith("Microsoft.SqlServer"));
        }

        [Test]
        public void SchemaJson_CanBeMaterializedInSqlite()
        {
            var schema = LoadSchema();
            var tables = schema.Tables.Where(t => t.TableType == "TABLE").ToList();

            using var connection = new SqliteConnection("Data Source=:memory:");
            connection.Open();
            foreach (var table in tables)
            {
                connection.Execute(CreateTableStatement(table));
                foreach (var index in table.Indexes.Where(i => i.LogicalType != "PRIMARY KEY"))
                    connection.Execute($"CREATE {(index.LogicalType == "UNIQUE" ? "UNIQUE " : "")}INDEX \"{index.IndexName}\" ON \"{table.TableName}\" ({string.Join(", ", index.Columns.Where(c => !c.IsIncludedColumn).Select(c => $"\"{c.ColumnName}\""))})");
            }

            var created = connection.Query<string>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").ToList();
            Assert.That(created, Is.EquivalentTo(tables.Select(t => t.TableName)));

            connection.Execute("INSERT INTO \"Product\" (\"Name\", \"ProductNumber\", \"SafetyStockLevel\", \"ReorderPoint\", \"StandardCost\", \"ListPrice\", \"DaysToManufacture\", \"SellStartDate\") VALUES ('Tesla Model S', 'TS-0001', 1, 1, 50000, 79990, 1, '2026-01-01')");
            var row = connection.QuerySingle("SELECT \"ProductID\", \"rowguid\", \"ModifiedDate\", \"MakeFlag\" FROM \"Product\"");
            Assert.That((long)row.ProductID, Is.EqualTo(1));
            Assert.That((string)row.rowguid, Has.Length.EqualTo(32));
            Assert.That((string)row.ModifiedDate, Is.Not.Empty);
            Assert.That((long)row.MakeFlag, Is.EqualTo(1));
        }

        private static string CreateTableStatement(Table table)
        {
            var primaryKey = table.Columns.Where(c => c.IsPrimaryKeyMember).OrderBy(c => c.PrimaryKeyOrdinalPosition).ToList();
            var definitions = new List<string>();
            foreach (var column in table.Columns.OrderBy(c => c.OrdinalPosition))
            {
                var definition = $"\"{column.ColumnName}\" {column.SqlDataType}";
                if (primaryKey.Count == 1 && column.IsPrimaryKeyMember && column.IsIdentity)
                    definition += " PRIMARY KEY AUTOINCREMENT";
                else if (!column.IsNullable)
                    definition += " NOT NULL";
                if (column.DefaultSetting != null)
                    definition += $" DEFAULT {column.DefaultSetting}";
                definitions.Add(definition);
            }
            if (primaryKey.Any() && !(primaryKey.Count == 1 && primaryKey[0].IsIdentity))
                definitions.Add($"PRIMARY KEY ({string.Join(", ", primaryKey.Select(c => $"\"{c.ColumnName}\""))})");
            return $"CREATE TABLE \"{table.TableName}\" ({string.Join(", ", definitions)})";
        }

        [Test]
        public void Generator_CreatesAPocoForEveryTable()
        {
            var result = CreateHarness().Run();

            Assert.That(result.GeneratorDiagnostics, Is.Empty, result.Describe());
            var source = result.GeneratedSources.Single(s => s.HintName == "SimplePOCOGenerator.g.cs").SourceText.ToString();
            var expectedClasses = LoadSchema().Tables
                .Where(t => t.TableType != "VIEW" && t.TableName != "Document" && t.TableName != "EmailAddress")
                .Select(t => t.TableName)
                .OrderBy(n => n)
                .ToList();
            var generatedClasses = Regex.Matches(source, @"public partial class (\w+)").Select(m => m.Groups[1].Value).OrderBy(n => n).ToList();

            Assert.That(source, Does.Contain("namespace MyProject.POCOs"));
            Assert.That(generatedClasses, Is.EqualTo(expectedClasses));
            Assert.That(source, Does.Not.Contain("Schema = \""), "SQLite tables live in the default schema");
        }

        [Test]
        public void OutputCompilation_HasNoErrors()
        {
            var result = CreateHarness().Run();

            Assert.That(result.CompilationErrors, Is.Empty, result.Describe());
        }

        [Test]
        public void EditingTheModel_RerunsTheTemplate()
        {
            var harness = CreateHarness();
            var compilation = harness.CreateCompilation();
            var first = GeneratorHarness.Run(harness.CreateDriver(), compilation);
            var model = _workspace.PathOf("AdventureWorksSchema.json");
            File.WriteAllText(model, File.ReadAllText(model).Replace("\"TableName\": \"Shift\"", "\"TableName\": \"WorkShift\""));

            var driver = first.Driver.ReplaceAdditionalText(harness.AdditionalTexts[model], GeneratorHarness.CreateAdditionalText(model));
            var second = GeneratorHarness.Run(driver, compilation);

            Assert.That(second.StepOutputs(CodegenGenerator.RunTemplateTrackingName).Single().Reason, Is.EqualTo(IncrementalStepRunReason.Modified));
            var source = second.GeneratedSources.Single(s => s.HintName == "SimplePOCOGenerator.g.cs").SourceText.ToString();
            Assert.That(source, Does.Contain("public partial class WorkShift").And.Not.Contain("public partial class Shift"));
        }

        [Test]
        public void EditingSourceFiles_DoesNotRerunTheTemplate()
        {
            var harness = CreateHarness();
            var compilation = harness.CreateCompilation();
            var first = GeneratorHarness.Run(harness.CreateDriver(), compilation);
            var updated = compilation.AddSyntaxTrees(CSharpSyntaxTree.ParseText(
                "namespace MyProject.POCOs { public partial class Product { public string Display => Name + \" (\" + ProductNumber + \")\"; } }",
                (CSharpParseOptions)compilation.SyntaxTrees.First().Options, _workspace.PathOf("ProductExtensions.cs")));

            var second = GeneratorHarness.Run(first.Driver, updated);

            Assert.That(second.StepOutputs(CodegenGenerator.RunTemplateTrackingName).Single().Reason, Is.EqualTo(IncrementalStepRunReason.Cached));
            Assert.That(second.CompilationErrors, Is.Empty, second.Describe());
        }

        [Test]
        public void GeneratedPocos_RoundTripThroughSqliteWithDapper()
        {
            var result = CreateHarness().Run();
            Assert.That(result.CompilationErrors, Is.Empty, result.Describe());

            var compilation = result.OutputCompilation.WithOptions(result.OutputCompilation.Options.WithOutputKind(OutputKind.ConsoleApplication));
            using var stream = new MemoryStream();
            var emit = compilation.Emit(stream);
            Assert.That(emit.Success, Is.True, string.Join(Environment.NewLine, emit.Diagnostics));

            var loadContext = new AssemblyLoadContext(nameof(GeneratedPocos_RoundTripThroughSqliteWithDapper), isCollectible: true);
            try
            {
                stream.Position = 0;
                var assembly = loadContext.LoadFromStream(stream);
                var output = new StringWriter();
                var previousOut = Console.Out;
                Console.SetOut(output);
                try
                {
                    assembly.EntryPoint.Invoke(null, new object[] { Array.Empty<string>() });
                }
                finally
                {
                    Console.SetOut(previousOut);
                }

                Assert.That(Lines(output.ToString()), Is.EqualTo(ExpectedOutput));
            }
            finally
            {
                loadContext.Unload();
            }
        }

        [Test]
        [Category("Integration")]
        public async Task DotnetBuildAndRun_QueriesSqliteUsingGeneratedPocos()
        {
            var build = await DotNetCli.BuildAsync(_workspace.Directory);

            Assert.That(build.ExitCode, Is.EqualTo(0), build.ToString());
            foreach (var code in DotNetCli.GeneratorFailureCodes)
                Assert.That(build.Output, Does.Not.Contain(code), build.ToString());
            Assert.That(build.Output, Does.Not.Contain("CODEGENCS"), build.ToString());

            var dll = Path.Combine(_workspace.Directory, "bin", TestPaths.Configuration, "net8.0", "SourceGenerator2.dll");
            var run = await DotNetCli.RunAsync(_workspace.Directory, dll);

            Assert.That(run.ExitCode, Is.EqualTo(0), run.ToString());
            Assert.That(Lines(run.Output), Is.EqualTo(ExpectedOutput));
        }

        private static string[] Lines(string text) =>
            text.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries).Select(l => l.Trim()).ToArray();
    }
}
