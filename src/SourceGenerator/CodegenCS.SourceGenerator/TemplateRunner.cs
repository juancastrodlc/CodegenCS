using CodegenCS.DotNet;
using CodegenCS.Runtime;
using CodegenCS.Utils;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using ExecutionContext = CodegenCS.Runtime.ExecutionContext;
using TemplateBuilderArgs = CodegenCS.TemplateBuilder.TemplateBuilder.TemplateBuilderArgs;
using TemplateLauncherArgs = CodegenCS.TemplateLauncher.TemplateLauncher.TemplateLauncherArgs;

namespace CodegenCS.CodeGenerator
{
    internal enum TemplateOutputMode
    {
        Memory,
        File,
    }

    internal sealed class GeneratedFile : IEquatable<GeneratedFile>
    {
        public GeneratedFile(string hintName, string fullPath, string contents)
        {
            HintName = hintName;
            FullPath = fullPath;
            Contents = contents;
        }

        public string HintName { get; }
        public string FullPath { get; }
        public string Contents { get; }

        public bool Equals(GeneratedFile other) =>
            other != null && HintName == other.HintName && FullPath == other.FullPath && Contents == other.Contents;

        public override bool Equals(object obj) => Equals(obj as GeneratedFile);

        public override int GetHashCode() => (HintName?.GetHashCode() ?? 0) ^ (FullPath?.GetHashCode() ?? 0) ^ (Contents?.Length ?? 0);
    }

    internal sealed class TemplateRunResult : IEquatable<TemplateRunResult>
    {
        public TemplateRunResult(string templatePath, TemplateOutputMode outputMode, IEnumerable<GeneratedFile> files, IEnumerable<DiagnosticInfo> diagnostics)
        {
            TemplatePath = templatePath;
            OutputMode = outputMode;
            Files = files?.ToArray() ?? new GeneratedFile[0];
            Diagnostics = diagnostics?.ToArray() ?? new DiagnosticInfo[0];
        }

        public string TemplatePath { get; }
        public TemplateOutputMode OutputMode { get; }
        public IReadOnlyList<GeneratedFile> Files { get; }
        public IReadOnlyList<DiagnosticInfo> Diagnostics { get; }
        public bool Succeeded => Diagnostics.Count == 0;

        public bool Equals(TemplateRunResult other) =>
            other != null && TemplatePath == other.TemplatePath && OutputMode == other.OutputMode &&
            Files.SequenceEqual(other.Files) && Diagnostics.SequenceEqual(other.Diagnostics);

        public override bool Equals(object obj) => Equals(obj as TemplateRunResult);

        public override int GetHashCode() => (TemplatePath?.GetHashCode() ?? 0) ^ Files.Count ^ (Diagnostics.Count << 16);
    }

    internal static class TemplateRunner
    {
        public static readonly string[] TemplateExtensions = { ".csx", ".cs", ".cgcs" };
        public const string OutputMetadata = "build_metadata.AdditionalFiles.CodegenCSOutput";

        private static readonly SemaphoreSlim _executionLock = new SemaphoreSlim(1, 1);

        public static bool IsTemplateExtension(string path)
        {
            var extension = Path.GetExtension(path);
            return !string.IsNullOrEmpty(extension) && TemplateExtensions.Contains(extension.ToLowerInvariant());
        }

        public static bool TryParseOutputMode(string value, out TemplateOutputMode mode)
        {
            mode = TemplateOutputMode.Memory;
            if (string.Equals(value, "Memory", StringComparison.OrdinalIgnoreCase))
                return true;
            if (string.Equals(value, "File", StringComparison.OrdinalIgnoreCase))
            {
                mode = TemplateOutputMode.File;
                return true;
            }
            return false;
        }

        public static string DefaultOutputFile(string templatePath) => Path.GetFileNameWithoutExtension(templatePath) + ".g.cs";

        public static TemplateRunResult Run(string templatePath, TemplateOutputMode outputMode, Action<DependencyContainer> registerServices, CancellationToken cancellationToken)
        {
            AnalyzerAssemblyResolver.EnsureRegistered();
            _executionLock.Wait(cancellationToken);
            try
            {
                return RunAsync(templatePath, outputMode, registerServices, cancellationToken).ConfigureAwait(false).GetAwaiter().GetResult();
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                return Failure(templatePath, outputMode, DiagnosticInfo.ExecutionError(templatePath, ex.GetBaseException().Message));
            }
            finally
            {
                _executionLock.Release();
            }
        }

        private static async Task<TemplateRunResult> RunAsync(string templatePath, TemplateOutputMode outputMode, Action<DependencyContainer> registerServices, CancellationToken cancellationToken)
        {
            var logger = new CapturingLogger();
            var executionFolder = Path.GetDirectoryName(Path.GetFullPath(templatePath));

            var templateDll = await BuildAsync(templatePath, logger, cancellationToken).ConfigureAwait(false);
            if (templateDll.Errors != null)
                return Failure(templatePath, outputMode, templateDll.Errors);

            cancellationToken.ThrowIfCancellationRequested();

            var codegenContext = new DotNetCodegenContext();
            var launcherArgs = new TemplateLauncherArgs()
            {
                Template = templateDll.Path,
                Models = new string[0],
                OutputFolder = executionFolder,
                ExecutionFolder = executionFolder,
                DefaultOutputFile = DefaultOutputFile(templatePath),
                SaveOutput = false,
            };
            var dependencyContainer = new DependencyContainer().AddModelFactory(new[] { executionFolder });
            dependencyContainer.RegisterSingleton<ExecutionContext>(() => new ExecutionContext(templatePath, executionFolder));
            registerServices?.Invoke(dependencyContainer);

            var launcher = new TemplateLauncher.TemplateLauncher(logger, codegenContext, dependencyContainer, verboseMode: false);
            int statusCode;
            try
            {
                statusCode = await launcher.LoadAndExecuteAsync(launcherArgs, null).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                return Failure(templatePath, outputMode, DiagnosticInfo.ExecutionError(templatePath, $"CodegenCS - error running template: {ex.GetBaseException().Message}"));
            }

            if (codegenContext.Errors.Any())
                return Failure(templatePath, outputMode, codegenContext.Errors.Select(e => DiagnosticInfo.ExecutionError(templatePath, $"CodegenCS - error running template: {e}")).ToArray());
            if (statusCode != 0)
                return Failure(templatePath, outputMode, DiagnosticInfo.ExecutionError(templatePath, $"CodegenCS - error running template: {logger.LastErrorOr("Unknown error")}"));

            var files = codegenContext.OutputFiles
                .Select(o => new GeneratedFile(
                    HintNameFor(o.RelativePath),
                    Path.GetFullPath(Path.Combine(executionFolder, o.RelativePath)),
                    o.GetContents()))
                .ToList();
            return new TemplateRunResult(templatePath, outputMode, files, null);
        }

        private sealed class BuiltTemplate
        {
            public string Path { get; set; }
            public DiagnosticInfo[] Errors { get; set; }
        }

        private static readonly Dictionary<string, string> _builtTemplates = new Dictionary<string, string>(StringComparer.Ordinal);

        private static async Task<BuiltTemplate> BuildAsync(string templatePath, CapturingLogger logger, CancellationToken cancellationToken)
        {
            var assemblyName = AssemblyNameFor(templatePath);
            lock (_builtTemplates)
            {
                if (_builtTemplates.TryGetValue(assemblyName, out var existing) && File.Exists(existing))
                    return new BuiltTemplate { Path = existing };
            }

            var output = Path.Combine(Path.GetTempPath(), "CodegenCS.SourceGenerator", Guid.NewGuid().ToString("N"), assemblyName + ".dll");
            var builderArgs = new TemplateBuilderArgs()
            {
                Template = new[] { templatePath },
                Output = output,
                VerboseMode = false,
                ExtraReferences = ExtraReferences(),
            };
            var builderResult = await new TemplateBuilder.TemplateBuilder(logger, builderArgs).ExecuteAsync().ConfigureAwait(false);
            if (builderResult.ReturnCode != 0)
            {
                var errors = builderResult.CompilationErrors?.Select(e => DiagnosticInfo.BuildError(templatePath, e.Message, e.Line, e.Column)).ToList();
                if (errors == null || errors.Count == 0)
                    errors = new List<DiagnosticInfo> { DiagnosticInfo.BuildError(templatePath, logger.LastErrorOr("Unknown error"), null, null) };
                return new BuiltTemplate { Errors = errors.ToArray() };
            }

            lock (_builtTemplates)
                _builtTemplates[assemblyName] = builderResult.TargetFile;
            return new BuiltTemplate { Path = builderResult.TargetFile };
        }

        private static string AssemblyNameFor(string templatePath)
        {
            var contents = File.ReadAllText(templatePath);
            string hash;
            using (var sha = SHA256.Create())
            {
                var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(typeof(TemplateRunner).Assembly.ManifestModule.ModuleVersionId + "|" + contents));
                hash = string.Concat(bytes.Take(8).Select(b => b.ToString("x2")));
            }
            var name = new string(Path.GetFileNameWithoutExtension(templatePath).Select(c => char.IsLetterOrDigit(c) || c == '_' ? c : '_').ToArray());
            return $"{name}_{hash}";
        }

        private static TemplateRunResult Failure(string templatePath, TemplateOutputMode outputMode, params DiagnosticInfo[] diagnostics) =>
            new TemplateRunResult(templatePath, outputMode, null, diagnostics);

        private static string HintNameFor(string relativePath) =>
            relativePath.Replace('\\', '/').TrimStart('/').Replace('/', '.');

        private static List<string> ExtraReferences()
        {
            var assemblies = new[]
            {
                typeof(TemplateRunner).GetTypeInfo().Assembly,
                typeof(AbstractLogger).GetTypeInfo().Assembly,
                typeof(Compilation).GetTypeInfo().Assembly,
                typeof(CSharpCompilation).GetTypeInfo().Assembly,
                typeof(ImmutableArray).GetTypeInfo().Assembly,
            };
            var locations = new List<string>();
            foreach (var assembly in assemblies)
            {
                var location = AnalyzerAssemblyResolver.GetLocation(assembly);
                if (!string.IsNullOrEmpty(location) && !locations.Contains(location))
                    locations.Add(location);
            }
            return locations;
        }

        private sealed class CapturingLogger : AbstractLogger
        {
            private readonly StringBuilder _buffer = new StringBuilder();
            private readonly List<string> _lines = new List<string>();

            public string LastErrorOr(string fallback)
            {
                lock (_buffer)
                {
                    FlushLine();
                    var meaningful = _lines.Where(l => !string.IsNullOrWhiteSpace(l)).ToList();
                    var errors = meaningful.Where(l => l.IndexOf("error", StringComparison.OrdinalIgnoreCase) >= 0).ToList();
                    var selected = errors.Any() ? errors : meaningful;
                    return selected.Any() ? string.Join(" ", selected.Skip(Math.Max(0, selected.Count - 3)).Select(l => l.Trim())) : fallback;
                }
            }

            protected override Task InnerWriteAsync(string message)
            {
                lock (_buffer)
                    _buffer.Append(message);
                return Task.CompletedTask;
            }

            protected override Task InnerWriteNewLineAsync()
            {
                lock (_buffer)
                    FlushLine();
                return Task.CompletedTask;
            }

            private void FlushLine()
            {
                if (_buffer.Length == 0)
                    return;
                _lines.Add(_buffer.ToString());
                _buffer.Clear();
            }

            protected override Task RefreshUIAsync() => Task.CompletedTask;

            protected override Task SetBackgroundColorAsync(ConsoleColor color) => Task.CompletedTask;

            protected override Task SetForegroundColorAsync(ConsoleColor color) => Task.CompletedTask;
        }
    }
}
