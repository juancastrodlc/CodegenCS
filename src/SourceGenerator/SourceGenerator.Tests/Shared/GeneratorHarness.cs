using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace CodegenCS.SourceGenerator.Tests
{
    internal sealed record TemplateItem(string Path, string Output);

    internal sealed class GeneratorHarnessResult
    {
        public GeneratorDriver Driver { get; init; }
        public Compilation InputCompilation { get; init; }
        public Compilation OutputCompilation { get; init; }
        public ImmutableArray<Diagnostic> GeneratorDiagnostics { get; init; }
        public GeneratorDriverRunResult RunResult { get; init; }

        public IReadOnlyList<Diagnostic> CompilationErrors =>
            OutputCompilation.GetDiagnostics().Where(d => d.Severity == DiagnosticSeverity.Error).ToList();

        public IReadOnlyList<GeneratedSourceResult> GeneratedSources =>
            RunResult.Results.SelectMany(r => r.GeneratedSources).ToList();

        public IReadOnlyList<(object Value, IncrementalStepRunReason Reason)> StepOutputs(string trackingName) =>
            RunResult.Results
                .SelectMany(r => r.TrackedSteps.TryGetValue(trackingName, out var steps) ? steps : ImmutableArray<IncrementalGeneratorRunStep>.Empty)
                .SelectMany(step => step.Outputs)
                .ToList();

        public string Describe() =>
            string.Join(Environment.NewLine,
                GeneratorDiagnostics.Select(d => "generator: " + d)
                .Concat(RunResult.Results.Where(r => r.Exception != null).Select(r => "exception: " + r.Exception))
                .Concat(CompilationErrors.Select(d => "compilation: " + d)));
    }

    internal sealed class GeneratorHarness
    {
        private readonly List<string> _sourceFiles = new();
        private readonly List<TemplateItem> _templates = new();
        private readonly List<string> _otherAdditionalFiles = new();
        private readonly Dictionary<string, string> _globalOptions = new();
        private ISourceGenerator _generator;

        public GeneratorHarness WithGenerator(ISourceGenerator generator)
        {
            _generator = generator;
            return this;
        }

        public GeneratorHarness AddSources(params string[] paths)
        {
            _sourceFiles.AddRange(paths);
            return this;
        }

        public GeneratorHarness AddTemplate(string path, string output)
        {
            _templates.Add(new TemplateItem(path, output));
            return this;
        }

        public GeneratorHarness AddAdditionalFile(string path)
        {
            _otherAdditionalFiles.Add(path);
            return this;
        }

        public GeneratorHarness WithGlobalOption(string key, string value)
        {
            _globalOptions[key] = value;
            return this;
        }

        public static IEnumerable<MetadataReference> DefaultReferences() =>
            ((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES"))
                .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
                .Where(File.Exists)
                .Select(p => MetadataReference.CreateFromFile(p));

        public CSharpCompilation CreateCompilation(string assemblyName = "BaseProject")
        {
            var parseOptions = new CSharpParseOptions(LanguageVersion.Preview);
            var trees = _sourceFiles.Select(path =>
                CSharpSyntaxTree.ParseText(SourceText.From(File.ReadAllText(path), Encoding.UTF8), parseOptions, Path.GetFullPath(path)));
            return CSharpCompilation.Create(assemblyName, trees, DefaultReferences(),
                new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary, nullableContextOptions: NullableContextOptions.Disable));
        }

        public Dictionary<string, AdditionalText> AdditionalTexts { get; } = new(StringComparer.Ordinal);

        public static AdditionalText CreateAdditionalText(string path) => new FileAdditionalText(path);

        public GeneratorDriver CreateDriver()
        {
            var additionalTexts = _templates.Select(t => CreateAdditionalText(t.Path))
                .Concat(_otherAdditionalFiles.Select(CreateAdditionalText))
                .ToImmutableArray();
            AdditionalTexts.Clear();
            foreach (var text in additionalTexts)
                AdditionalTexts[text.Path] = text;
            var perFile = _templates
                .Where(t => t.Output != null)
                .ToDictionary(t => Path.GetFullPath(t.Path), t => (IReadOnlyDictionary<string, string>)new Dictionary<string, string>
                {
                    ["build_metadata.AdditionalFiles.CodegenCSOutput"] = t.Output,
                });
            var optionsProvider = new TestOptionsProvider(perFile, _globalOptions);
            return CSharpGeneratorDriver.Create(
                new[] { _generator ?? TestGenerator.Create() },
                additionalTexts,
                new CSharpParseOptions(LanguageVersion.Preview),
                optionsProvider,
                new GeneratorDriverOptions(IncrementalGeneratorOutputKind.None, trackIncrementalGeneratorSteps: true));
        }

        public GeneratorHarnessResult Run() => Run(CreateDriver(), CreateCompilation());

        public static GeneratorHarnessResult Run(GeneratorDriver driver, Compilation compilation, CancellationToken cancellationToken = default)
        {
            driver = driver.RunGeneratorsAndUpdateCompilation(compilation, out var output, out var diagnostics, cancellationToken);
            return new GeneratorHarnessResult
            {
                Driver = driver,
                InputCompilation = compilation,
                OutputCompilation = output,
                GeneratorDiagnostics = diagnostics,
                RunResult = driver.GetRunResult(),
            };
        }

        private sealed class FileAdditionalText : AdditionalText
        {
            public FileAdditionalText(string path)
            {
                Path = System.IO.Path.GetFullPath(path);
            }

            public override string Path { get; }

            public override SourceText GetText(CancellationToken cancellationToken = default) =>
                SourceText.From(File.ReadAllText(Path), Encoding.UTF8);
        }

        private sealed class TestOptionsProvider : AnalyzerConfigOptionsProvider
        {
            private readonly IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> _perFile;

            public TestOptionsProvider(IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> perFile, IReadOnlyDictionary<string, string> global)
            {
                _perFile = perFile;
                GlobalOptions = new DictionaryOptions(global);
            }

            public override AnalyzerConfigOptions GlobalOptions { get; }

            public override AnalyzerConfigOptions GetOptions(SyntaxTree tree) => DictionaryOptions.Empty;

            public override AnalyzerConfigOptions GetOptions(AdditionalText textFile) =>
                _perFile.TryGetValue(textFile.Path, out var values) ? new DictionaryOptions(values) : DictionaryOptions.Empty;
        }

        private sealed class DictionaryOptions : AnalyzerConfigOptions
        {
            public static readonly DictionaryOptions Empty = new(new Dictionary<string, string>());
            private readonly IReadOnlyDictionary<string, string> _values;

            public DictionaryOptions(IReadOnlyDictionary<string, string> values)
            {
                _values = values;
            }

            public override bool TryGetValue(string key, out string value) => _values.TryGetValue(key, out value);
        }
    }
}
