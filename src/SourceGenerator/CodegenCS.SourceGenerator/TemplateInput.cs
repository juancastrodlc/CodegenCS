using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;
using System;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;

namespace CodegenCS.CodeGenerator
{
    /// <summary>
    /// An AdditionalFiles item, as seen by the incremental pipeline.
    /// Templates are the items with a template extension and CodegenCSOutput metadata; every other item is a dependency
    /// (e.g. a model loaded by a template) and is only tracked by its checksum.
    /// </summary>
    internal sealed class TemplateInput : IEquatable<TemplateInput>
    {
        private static readonly Regex _usesCompilation = new Regex(@"\bMicrosoft\.CodeAnalysis\b|\b(CSharp)?Compilation\b", RegexOptions.Compiled);
        private static readonly Regex _usesGeneratorExecutionContext = new Regex(@"\bGeneratorExecutionContext\b", RegexOptions.Compiled);

        private TemplateInput(string path, bool isTemplate, TemplateOutputMode outputMode, string invalidOutput, string checksum, bool usesCompilation, bool usesGeneratorExecutionContext)
        {
            Path = path;
            IsTemplate = isTemplate;
            OutputMode = outputMode;
            InvalidOutput = invalidOutput;
            Checksum = checksum;
            UsesCompilation = usesCompilation;
            UsesGeneratorExecutionContext = usesGeneratorExecutionContext;
        }

        public string Path { get; }
        public bool IsTemplate { get; }
        public TemplateOutputMode OutputMode { get; }
        public string InvalidOutput { get; }
        public string Checksum { get; }
        public bool UsesCompilation { get; }
        public bool UsesGeneratorExecutionContext { get; }

        public static TemplateInput Create(AdditionalText file, AnalyzerConfigOptions options, CancellationToken cancellationToken)
        {
            var text = file.GetText(cancellationToken);
            var checksum = text == null ? "" : string.Concat(text.GetChecksum().Select(b => b.ToString("x2")));

            string outputType = null;
            var isTemplate = TemplateRunner.IsTemplateExtension(file.Path)
                && options.TryGetValue(TemplateRunner.OutputMetadata, out outputType)
                && !string.IsNullOrWhiteSpace(outputType);
            if (!isTemplate)
                return new TemplateInput(file.Path, false, TemplateOutputMode.Memory, null, checksum, false, false);

            var validOutput = TemplateRunner.TryParseOutputMode(outputType, out var outputMode);
            var source = text?.ToString() ?? "";
            return new TemplateInput(file.Path, true, outputMode, validOutput ? null : outputType, checksum,
                _usesCompilation.IsMatch(source), _usesGeneratorExecutionContext.IsMatch(source));
        }

        public bool Equals(TemplateInput other) =>
            other != null && Path == other.Path && IsTemplate == other.IsTemplate && OutputMode == other.OutputMode &&
            InvalidOutput == other.InvalidOutput && Checksum == other.Checksum && UsesCompilation == other.UsesCompilation &&
            UsesGeneratorExecutionContext == other.UsesGeneratorExecutionContext;

        public override bool Equals(object obj) => Equals(obj as TemplateInput);

        public override int GetHashCode() => (Path?.GetHashCode() ?? 0) ^ (Checksum?.GetHashCode() ?? 0);
    }

    internal sealed class FileFingerprint : IEquatable<FileFingerprint>
    {
        public FileFingerprint(string path, string checksum)
        {
            Path = path;
            Checksum = checksum;
        }

        public string Path { get; }
        public string Checksum { get; }

        public bool Equals(FileFingerprint other) => other != null && Path == other.Path && Checksum == other.Checksum;

        public override bool Equals(object obj) => Equals(obj as FileFingerprint);

        public override int GetHashCode() => (Path?.GetHashCode() ?? 0) ^ (Checksum?.GetHashCode() ?? 0);
    }

    internal sealed class StringValue : IEquatable<StringValue>
    {
        public StringValue(string value)
        {
            Value = value;
        }

        public string Value { get; }

        public bool Equals(StringValue other) => other != null && TemplateOutputWriter.PathComparer.Equals(Value, other.Value);

        public override bool Equals(object obj) => Equals(obj as StringValue);

        public override int GetHashCode() => Value == null ? 0 : TemplateOutputWriter.PathComparer.GetHashCode(Value);
    }
}
