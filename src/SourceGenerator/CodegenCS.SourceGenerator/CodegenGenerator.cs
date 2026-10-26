using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace CodegenCS.CodeGenerator
{
    /// <summary>
    /// Runs CodegenCS templates (AdditionalFiles items with CodegenCSOutput metadata) during compilation.
    /// </summary>
    [Generator(LanguageNames.CSharp)]
    public sealed class CodegenGenerator : IIncrementalGenerator
    {
        public const string TemplatesTrackingName = "CodegenCS.Templates";
        public const string DependenciesTrackingName = "CodegenCS.Dependencies";
        public const string RunTemplateTrackingName = "CodegenCS.RunTemplate";
        public const string RunCompilationAwareTemplateTrackingName = "CodegenCS.RunCompilationAwareTemplate";

        public void Initialize(IncrementalGeneratorInitializationContext context)
        {
            var additionalFiles = context.AdditionalTextsProvider
                .Combine(context.AnalyzerConfigOptionsProvider)
                .Select((pair, cancellationToken) => TemplateInput.Create(pair.Left, pair.Right.GetOptions(pair.Left), cancellationToken));

            var templates = additionalFiles
                .Where(input => input.IsTemplate)
                .WithTrackingName(TemplatesTrackingName);

            var dependencies = additionalFiles
                .Where(input => !input.IsTemplate)
                .Select((input, _) => new FileFingerprint(input.Path, input.Checksum))
                .Collect()
                .Select((items, _) => new EquatableArray<FileFingerprint>(items.OrderBy(i => i.Path, StringComparer.Ordinal)))
                .WithTrackingName(DependenciesTrackingName);

            var compilationFiles = context.CompilationProvider
                .Select((compilation, _) => new EquatableArray<StringValue>(compilation.SyntaxTrees
                    .Select(tree => new StringValue(TemplateOutputWriter.NormalizePath(tree.FilePath)))
                    .OrderBy(path => path.Value, StringComparer.Ordinal)));

            var templatesWithDependencies = templates.Combine(dependencies);

            var results = templatesWithDependencies
                .Where(pair => !pair.Left.UsesCompilation)
                .Select((pair, cancellationToken) => Run(pair.Left, null, cancellationToken))
                .WithTrackingName(RunTemplateTrackingName);

            var compilationAwareResults = templatesWithDependencies
                .Where(pair => pair.Left.UsesCompilation)
                .Combine(context.CompilationProvider)
                .Select((pair, cancellationToken) => Run(pair.Left.Left, pair.Right, cancellationToken))
                .WithTrackingName(RunCompilationAwareTemplateTrackingName);

            context.RegisterSourceOutput(results.Combine(compilationFiles), Emit);
            context.RegisterSourceOutput(compilationAwareResults.Combine(compilationFiles), Emit);
        }

        private static TemplateRunResult Run(TemplateInput template, Compilation compilation, CancellationToken cancellationToken)
        {
            if (template.InvalidOutput != null)
                return new TemplateRunResult(template.Path, template.OutputMode, null, new[] { DiagnosticInfo.ExecutionError(template.Path, $"Invalid Output: {template.InvalidOutput}") });
            if (template.UsesGeneratorExecutionContext)
                return new TemplateRunResult(template.Path, template.OutputMode, null, new[] { DiagnosticInfo.UnsupportedGeneratorExecutionContext(template.Path) });

            return TemplateRunner.Run(template.Path, template.OutputMode, container =>
            {
                if (compilation == null)
                    return;
                container.RegisterSingleton<Compilation>(() => compilation);
                if (compilation is CSharpCompilation csharpCompilation)
                    container.RegisterSingleton<CSharpCompilation>(() => csharpCompilation);
            }, cancellationToken);
        }

        private static void Emit(SourceProductionContext context, (TemplateRunResult Result, EquatableArray<StringValue> CompilationFiles) input)
        {
            var compilationFiles = new HashSet<string>(input.CompilationFiles.Select(f => f.Value), TemplateOutputWriter.PathComparer);
            TemplateOutputWriter.Emit(input.Result, compilationFiles, context.AddSource, context.ReportDiagnostic);
        }
    }
}
