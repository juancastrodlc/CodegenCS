using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;
using System;
using System.Linq;

namespace CodegenCS.CodeGenerator
{
    internal static class Diagnostics
    {
        public static readonly DiagnosticDescriptor BuildFailure =
            new DiagnosticDescriptor(id: "CODEGENCS001",
                                    title: "Failed to build CodegenCS Template",
                                    messageFormat: "Failed to build CodegenCS Template '{0}': '{1}'",
                                    category: "Design",
                                    DiagnosticSeverity.Error,
                                    isEnabledByDefault: true);

        public static readonly DiagnosticDescriptor BuildFailureWithLine =
            new DiagnosticDescriptor(id: "CODEGENCS002",
                                    title: "Failed to build CodegenCS Template",
                                    messageFormat: "Failed to build CodegenCS Template '{0}' (line {1} column {2}): '{3}'",
                                    category: "Design",
                                    DiagnosticSeverity.Error,
                                    isEnabledByDefault: true);

        public static readonly DiagnosticDescriptor ExecutionFailure =
            new DiagnosticDescriptor(id: "CODEGENCS003",
                                    title: "Failed to run CodegenCS Template",
                                    messageFormat: "Failed to run CodegenCS Template '{0}': '{1}'",
                                    category: "Design",
                                    DiagnosticSeverity.Error,
                                    isEnabledByDefault: true);

        public static readonly DiagnosticDescriptor UnsupportedGeneratorExecutionContext =
            new DiagnosticDescriptor(id: "CODEGENCS004",
                                    title: "GeneratorExecutionContext is not available to CodegenCS Templates",
                                    messageFormat: "CodegenCS Template '{0}' uses GeneratorExecutionContext, which doesn't exist in incremental source generators. Inject Microsoft.CodeAnalysis.Compilation instead (e.g. 'void Main(ICodegenContext context, Compilation compilation)').",
                                    category: "Design",
                                    DiagnosticSeverity.Error,
                                    isEnabledByDefault: true);

        public static DiagnosticDescriptor FromId(string id) => id switch
        {
            "CODEGENCS001" => BuildFailure,
            "CODEGENCS002" => BuildFailureWithLine,
            "CODEGENCS004" => UnsupportedGeneratorExecutionContext,
            _ => ExecutionFailure,
        };
    }

    internal sealed class DiagnosticInfo : IEquatable<DiagnosticInfo>
    {
        public DiagnosticInfo(DiagnosticDescriptor descriptor, string filePath, int? line, int? column, params string[] arguments)
        {
            Id = descriptor.Id;
            FilePath = filePath;
            Line = line;
            Column = column;
            Arguments = arguments ?? new string[0];
        }

        public string Id { get; }
        public string FilePath { get; }
        public int? Line { get; }
        public int? Column { get; }
        public string[] Arguments { get; }

        public static DiagnosticInfo BuildError(string templatePath, string message, int? line, int? column) =>
            line == null && column == null
                ? new DiagnosticInfo(Diagnostics.BuildFailure, templatePath, null, null, templatePath, message)
                : new DiagnosticInfo(Diagnostics.BuildFailureWithLine, templatePath, line, column, templatePath, line?.ToString(), column?.ToString(), message);

        public static DiagnosticInfo UnsupportedGeneratorExecutionContext(string templatePath) =>
            new DiagnosticInfo(Diagnostics.UnsupportedGeneratorExecutionContext, templatePath, null, null, templatePath);

        public static DiagnosticInfo ExecutionError(string templatePath, string message) =>
            new DiagnosticInfo(Diagnostics.ExecutionFailure, templatePath, null, null, templatePath ?? "", message);

        public Diagnostic ToDiagnostic()
        {
            var location = Location.None;
            if (!string.IsNullOrEmpty(FilePath))
            {
                var position = new LinePosition(Math.Max(0, (Line ?? 1) - 1), Math.Max(0, (Column ?? 1) - 1));
                location = Location.Create(FilePath, default(TextSpan), new LinePositionSpan(position, position));
            }
            return Diagnostic.Create(Diagnostics.FromId(Id), location, Arguments.Cast<object>().ToArray());
        }

        public bool Equals(DiagnosticInfo other) =>
            other != null && Id == other.Id && FilePath == other.FilePath && Line == other.Line && Column == other.Column && Arguments.SequenceEqual(other.Arguments);

        public override bool Equals(object obj) => Equals(obj as DiagnosticInfo);

        public override int GetHashCode()
        {
            unchecked
            {
                int hash = 17;
                hash = hash * 23 + (Id?.GetHashCode() ?? 0);
                hash = hash * 23 + (FilePath?.GetHashCode() ?? 0);
                hash = hash * 23 + (Line ?? 0);
                hash = hash * 23 + (Column ?? 0);
                foreach (var argument in Arguments)
                    hash = hash * 23 + (argument?.GetHashCode() ?? 0);
                return hash;
            }
        }
    }
}
