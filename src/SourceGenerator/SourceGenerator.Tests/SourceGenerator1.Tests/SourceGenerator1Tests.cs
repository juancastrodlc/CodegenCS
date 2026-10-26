using CodegenCS.CodeGenerator;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using NUnit.Framework;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace CodegenCS.SourceGenerator.Tests
{
    [TestFixture]
    internal class SourceGenerator1Tests
    {
        private TestWorkspace _workspace;

        [SetUp]
        public void SetUp() => _workspace = TestWorkspace.FromBaseProject();

        [TearDown]
        public void TearDown() => _workspace.Dispose();

        private GeneratorHarness CreateHarness() => new GeneratorHarness()
            .AddSources(_workspace.PathOf("SampleClass.cs"), _workspace.PathOf("AnotherSampleClass.cs"))
            .AddTemplate(_workspace.PathOf("Template1.csx"), "File")
            .AddTemplate(_workspace.PathOf("Template2.csx"), "Memory")
            .AddTemplate(_workspace.PathOf("Template3.csx"), "Memory");

        private static string GeneratedSource(GeneratorHarnessResult result, string hintName) =>
            result.GeneratedSources.SingleOrDefault(s => s.HintName == hintName).SourceText?.ToString();

        [Test]
        public void Templates_RunWithoutGeneratorDiagnosticsOrExceptions()
        {
            var result = CreateHarness().Run();

            Assert.That(result.RunResult.Results.Select(r => r.Exception), Is.All.Null, result.Describe());
            Assert.That(result.GeneratorDiagnostics, Is.Empty, result.Describe());
        }

        [Test]
        public void OutputCompilation_HasNoErrors_OnACleanProject()
        {
            var result = CreateHarness().Run();

            Assert.That(result.CompilationErrors, Is.Empty, result.Describe());
        }

        [Test]
        public void FileOutput_IsSavedToDisk_NextToTheTemplate()
        {
            CreateHarness().Run();

            var file = _workspace.PathOf("Template1.g.cs");
            Assert.That(File.Exists(file), Is.True);
            Assert.That(File.ReadAllText(file), Does.Contain("public class MyFirstClass"));
        }

        [Test]
        public void FileOutput_IsAddedToCompilation_WhenNotYetPartOfIt()
        {
            var result = CreateHarness().Run();

            Assert.That(GeneratedSource(result, "Template1.g.cs"), Does.Contain("public class MyFirstClass"));
            Assert.That(result.OutputCompilation.GetTypeByMetadataName("MyFirstClass"), Is.Not.Null);
        }

        [Test]
        public void FileOutput_IsNotDuplicated_WhenAlreadyPartOfCompilation()
        {
            CreateHarness().Run();
            Assert.That(File.Exists(_workspace.PathOf("Template1.g.cs")), Is.True);

            var secondRun = CreateHarness().AddSources(_workspace.PathOf("Template1.g.cs")).Run();

            Assert.That(secondRun.GeneratedSources.Select(s => s.HintName), Does.Not.Contain("Template1.g.cs"));
            Assert.That(secondRun.CompilationErrors, Is.Empty, secondRun.Describe());
        }

        [Test]
        public void MemoryOutput_IsAddedToCompilation_AndNotSavedToDisk()
        {
            var result = CreateHarness().Run();

            Assert.That(GeneratedSource(result, "Template2.g.cs"), Does.Contain("public class MySecondClass"));
            Assert.That(File.Exists(_workspace.PathOf("Template2.g.cs")), Is.False);
        }

        [Test]
        public void MemoryOutput_RemovesFilePreviouslyGeneratedWithFileOutput()
        {
            File.WriteAllText(_workspace.PathOf("Template2.g.cs"), "public class MySecondClass {}");

            var result = new GeneratorHarness()
                .AddTemplate(_workspace.PathOf("Template2.csx"), "Memory")
                .Run();

            Assert.That(GeneratedSource(result, "Template2.g.cs"), Does.Contain("public class MySecondClass"));
            Assert.That(File.Exists(_workspace.PathOf("Template2.g.cs")), Is.False);
        }

        [Test]
        public void CompilationAwareTemplate_AugmentsEveryPartialClass()
        {
            var result = CreateHarness().Run();

            Assert.That(GeneratedSource(result, "SampleClass.g.cs"), Does.Contain("partial class SampleClass").And.Contain("public void Initialize()"));
            Assert.That(GeneratedSource(result, "AnotherSampleClass.g.cs"), Does.Contain("partial class AnotherSampleClass").And.Contain("public void Initialize()"));
        }

        [Test]
        public void AdditionalFile_WithoutCodegenCSOutputMetadata_IsIgnored()
        {
            var result = new GeneratorHarness()
                .AddTemplate(_workspace.PathOf("Template2.csx"), output: null)
                .Run();

            Assert.That(result.GeneratorDiagnostics, Is.Empty, result.Describe());
            Assert.That(result.GeneratedSources, Is.Empty);
        }

        [Test]
        public void AdditionalFile_WithUnsupportedExtension_IsIgnored()
        {
            var json = _workspace.PathOf("settings.json");
            File.WriteAllText(json, "{}");

            var result = new GeneratorHarness().AddTemplate(json, "Memory").Run();

            Assert.That(result.GeneratorDiagnostics, Is.Empty, result.Describe());
            Assert.That(result.GeneratedSources, Is.Empty);
        }

        [Test]
        public void InvalidCodegenCSOutput_ReportsExecutionFailure()
        {
            var result = new GeneratorHarness()
                .AddTemplate(_workspace.PathOf("Template2.csx"), "Disk")
                .Run();

            var diagnostic = result.GeneratorDiagnostics.Single();
            Assert.That(diagnostic.Id, Is.EqualTo("CODEGENCS003"));
            Assert.That(diagnostic.GetMessage(), Does.Contain("Invalid Output: Disk"));
            Assert.That(result.GeneratedSources, Is.Empty);
        }

        [Test]
        public void TemplateWithCompilationErrors_ReportsBuildFailureAtTheTemplateLocation()
        {
            var broken = _workspace.PathOf("Broken.csx");
            File.WriteAllText(broken, """
                class Broken
                {
                    FormattableString Main() => $"{UndefinedSymbol}";
                }
                """);

            var result = new GeneratorHarness().AddTemplate(broken, "Memory").Run();

            var diagnostic = result.GeneratorDiagnostics.First();
            Assert.That(diagnostic.Id, Is.EqualTo("CODEGENCS002"));
            Assert.That(diagnostic.Severity, Is.EqualTo(DiagnosticSeverity.Error));
            Assert.That(diagnostic.GetMessage(), Does.Contain("UndefinedSymbol"));
            Assert.That(diagnostic.Location.GetLineSpan().Path, Is.EqualTo(broken));
            Assert.That(diagnostic.Location.GetLineSpan().StartLinePosition.Line, Is.EqualTo(2));
            Assert.That(result.GeneratedSources, Is.Empty);
        }

        [Test]
        public void TemplateUsingGeneratorExecutionContext_ReportsHowToMigrate()
        {
            var legacy = _workspace.PathOf("Legacy.csx");
            File.WriteAllText(legacy, """
                using Microsoft.CodeAnalysis;
                class Legacy
                {
                    void Main(ICodegenContext context, GeneratorExecutionContext generatorContext) { }
                }
                """);

            var result = new GeneratorHarness().AddTemplate(legacy, "Memory").Run();

            var diagnostic = result.GeneratorDiagnostics.Single();
            Assert.That(diagnostic.Id, Is.EqualTo("CODEGENCS004"));
            Assert.That(diagnostic.GetMessage(), Does.Contain("Compilation"));
            Assert.That(diagnostic.Location.GetLineSpan().Path, Is.EqualTo(legacy));
        }

        [Test]
        public void CompilationAwareTemplate_CanInjectCSharpCompilation()
        {
            var template = _workspace.PathOf("CountClasses.csx");
            File.WriteAllText(template, """
                using Microsoft.CodeAnalysis.CSharp;
                class CountClasses
                {
                    FormattableString Main(CSharpCompilation compilation) =>
                        $"public static class Info {{ public const string Language = \"{compilation.Language}\"; public const int Trees = {compilation.SyntaxTrees.Count()}; }}";
                }
                """);

            var result = new GeneratorHarness()
                .AddSources(_workspace.PathOf("SampleClass.cs"), _workspace.PathOf("AnotherSampleClass.cs"))
                .AddTemplate(template, "Memory")
                .Run();

            Assert.That(result.GeneratorDiagnostics, Is.Empty, result.Describe());
            Assert.That(GeneratedSource(result, "CountClasses.g.cs"), Does.Contain("Language = \"C#\"").And.Contain("Trees = 2"));
        }

        [Test]
        public void SecondRun_WithoutChanges_ReusesEveryTemplateResult()
        {
            var harness = CreateHarness();
            var compilation = harness.CreateCompilation();
            var first = GeneratorHarness.Run(harness.CreateDriver(), compilation);
            Assert.That(first.GeneratorDiagnostics, Is.Empty, first.Describe());

            var second = GeneratorHarness.Run(first.Driver, compilation);

            var outputs = second.StepOutputs(CodegenGenerator.RunTemplateTrackingName)
                .Concat(second.StepOutputs(CodegenGenerator.RunCompilationAwareTemplateTrackingName))
                .ToList();
            Assert.That(outputs, Has.Count.EqualTo(3));
            Assert.That(outputs.Select(o => o.Reason), Is.All.EqualTo(IncrementalStepRunReason.Cached));
            Assert.That(second.GeneratedSources.Select(s => s.HintName), Is.EquivalentTo(first.GeneratedSources.Select(s => s.HintName)));
        }

        [Test]
        public void SourceChanges_OnlyRerunTemplatesThatUseTheCompilation()
        {
            var harness = CreateHarness();
            var compilation = harness.CreateCompilation();
            var first = GeneratorHarness.Run(harness.CreateDriver(), compilation);
            var newFile = _workspace.PathOf("NewClass.cs");
            var updated = compilation.AddSyntaxTrees(CSharpSyntaxTree.ParseText(
                "namespace SampleProjectWithSourceGenerator { public partial class NewClass { } }",
                (CSharpParseOptions)compilation.SyntaxTrees.First().Options, newFile));

            var second = GeneratorHarness.Run(first.Driver, updated);

            Assert.That(second.StepOutputs(CodegenGenerator.RunTemplateTrackingName).Select(o => o.Reason), Is.All.EqualTo(IncrementalStepRunReason.Cached));
            Assert.That(second.StepOutputs(CodegenGenerator.RunCompilationAwareTemplateTrackingName).Select(o => o.Reason), Is.All.EqualTo(IncrementalStepRunReason.Modified));
            Assert.That(GeneratedSource(second, "NewClass.g.cs"), Does.Contain("partial class NewClass"));
            Assert.That(second.CompilationErrors, Is.Empty, second.Describe());
        }

        [Test]
        public void EditingATemplate_RerunsOnlyThatTemplate()
        {
            var harness = CreateHarness();
            var compilation = harness.CreateCompilation();
            var first = GeneratorHarness.Run(harness.CreateDriver(), compilation);
            var template2 = _workspace.PathOf("Template2.csx");
            File.WriteAllText(template2, File.ReadAllText(template2).Replace("public class MySecondClass {}", "public class MySecondClass { public int Version => 2; }"));

            var driver = first.Driver.ReplaceAdditionalText(harness.AdditionalTexts[template2], GeneratorHarness.CreateAdditionalText(template2));
            var second = GeneratorHarness.Run(driver, compilation);

            var reasons = second.StepOutputs(CodegenGenerator.RunTemplateTrackingName)
                .ToDictionary(o => Path.GetFileName(((TemplateRunResult)o.Value).TemplatePath), o => o.Reason);
            Assert.That(reasons["Template1.csx"], Is.EqualTo(IncrementalStepRunReason.Cached));
            Assert.That(reasons["Template2.csx"], Is.EqualTo(IncrementalStepRunReason.Modified));
            Assert.That(GeneratedSource(second, "Template2.g.cs"), Does.Contain("public int Version => 2;"));
        }

        [Test]
        public void PortableBuild_RunsInAHostWithTheReferencedRoslynVersion()
        {
            var result = CreateHarness().WithGenerator(PortableGenerator.Load()).Run();

            Assert.That(result.RunResult.Results.Select(r => r.Exception), Is.All.Null, result.Describe());
            Assert.That(result.GeneratorDiagnostics, Is.Empty, result.Describe());
            Assert.That(result.CompilationErrors, Is.Empty, result.Describe());
            Assert.That(result.GeneratedSources.Select(s => s.HintName), Is.EquivalentTo(new[] { "Template1.g.cs", "Template2.g.cs", "SampleClass.g.cs", "AnotherSampleClass.g.cs" }));
        }

        [TestCase(false, TestName = "DotnetBuild_RunsTheGeneratorInsideTheSdkCompiler")]
        [TestCase(true, TestName = "DotnetBuild_RunsTheGeneratorInsideTheSdkCompilerServer")]
        [Category("Integration")]
        public async Task DotnetBuild_RunsTheGeneratorInsideTheSdkCompiler(bool sharedCompilation)
        {
            try
            {
                await BuildTwiceAndVerify(sharedCompilation);
            }
            finally
            {
                if (sharedCompilation)
                    await DotNetCli.ShutdownBuildServersAsync(_workspace.Directory);
            }
        }

        private async Task BuildTwiceAndVerify(bool sharedCompilation)
        {
            var firstBuild = await DotNetCli.BuildAsync(_workspace.Directory, sharedCompilation);

            Assert.That(firstBuild.ExitCode, Is.EqualTo(0), firstBuild.ToString());
            foreach (var code in DotNetCli.GeneratorFailureCodes)
                Assert.That(firstBuild.Output, Does.Not.Contain(code), firstBuild.ToString());
            Assert.That(firstBuild.Output, Does.Not.Contain("CODEGENCS"), firstBuild.ToString());
            Assert.That(File.ReadAllText(_workspace.PathOf("Template1.g.cs")), Does.Contain("public class MyFirstClass"));

            var incrementalBuild = await DotNetCli.BuildAsync(_workspace.Directory, sharedCompilation);

            Assert.That(incrementalBuild.ExitCode, Is.EqualTo(0), incrementalBuild.ToString());
            Assert.That(incrementalBuild.Output, Does.Not.Contain("CS0101"), incrementalBuild.ToString());
        }
    }
}
