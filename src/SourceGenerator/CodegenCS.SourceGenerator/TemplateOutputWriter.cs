using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace CodegenCS.CodeGenerator
{
    internal static class TemplateOutputWriter
    {
        public static readonly StringComparer PathComparer =
            Path.DirectorySeparatorChar == '\\' ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

        public static string NormalizePath(string path)
        {
            if (string.IsNullOrEmpty(path))
                return path;
            try
            {
                return Path.GetFullPath(path);
            }
            catch (Exception)
            {
                return path;
            }
        }

        public static void Emit(TemplateRunResult result, ICollection<string> compilationFiles, Action<string, SourceText> addSource, Action<Diagnostic> reportDiagnostic)
        {
            foreach (var diagnostic in result.Diagnostics)
                reportDiagnostic(diagnostic.ToDiagnostic());
            if (!result.Succeeded)
                return;

            foreach (var file in result.Files)
            {
                var text = SourceText.From(file.Contents, Encoding.UTF8);
                try
                {
                    if (result.OutputMode == TemplateOutputMode.Memory)
                    {
                        addSource(file.HintName, text);
                        if (File.Exists(file.FullPath))
                            File.Delete(file.FullPath);
                        continue;
                    }

                    WriteIfChanged(file.FullPath, file.Contents);
                    if (!compilationFiles.Contains(file.FullPath))
                        addSource(file.HintName, text);
                }
                catch (IOException ex)
                {
                    reportDiagnostic(DiagnosticInfo.ExecutionError(result.TemplatePath, $"Could not write '{file.FullPath}': {ex.Message}").ToDiagnostic());
                }
                catch (UnauthorizedAccessException ex)
                {
                    reportDiagnostic(DiagnosticInfo.ExecutionError(result.TemplatePath, $"Could not write '{file.FullPath}': {ex.Message}").ToDiagnostic());
                }
            }
        }

        private static void WriteIfChanged(string path, string contents)
        {
            if (File.Exists(path) && File.ReadAllText(path) == contents)
                return;
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory))
                Directory.CreateDirectory(directory);
            File.WriteAllText(path, contents, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        }
    }
}
