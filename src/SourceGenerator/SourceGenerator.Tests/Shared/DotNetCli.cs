using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Threading.Tasks;

namespace CodegenCS.SourceGenerator.Tests
{
    internal sealed record DotNetCliResult(int ExitCode, string Output)
    {
        public override string ToString() => $"exit code {ExitCode}{Environment.NewLine}{Output}";
    }

    internal static class DotNetCli
    {
        public static readonly string[] GeneratorFailureCodes = { "CS9057", "CS8032", "CS8033", "CS8034", "CS8784", "CS8785" };

        public static async Task<DotNetCliResult> RunAsync(string workingDirectory, params string[] arguments)
        {
            var startInfo = new ProcessStartInfo("dotnet")
            {
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            foreach (var argument in arguments)
                startInfo.ArgumentList.Add(argument);
            startInfo.Environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1";
            startInfo.Environment["DOTNET_NOLOGO"] = "1";
            startInfo.Environment["DOTNET_SKIP_FIRST_TIME_EXPERIENCE"] = "1";
            startInfo.Environment["DOTNET_CLI_UI_LANGUAGE"] = "en";
            startInfo.Environment["MSBUILDDISABLENODEREUSE"] = "1";
            startInfo.Environment.Remove("MSBuildSDKsPath");
            startInfo.Environment.Remove("MSBuildExtensionsPath");
            startInfo.Environment.Remove("MSBUILD_EXE_PATH");

            var output = new StringBuilder();
            using var process = new Process { StartInfo = startInfo };
            process.OutputDataReceived += (_, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
            process.ErrorDataReceived += (_, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            await process.WaitForExitAsync();
            return new DotNetCliResult(process.ExitCode, output.ToString());
        }

        public static Task<DotNetCliResult> BuildAsync(string projectDirectory, params string[] extraArguments) =>
            BuildAsync(projectDirectory, sharedCompilation: false, extraArguments);

        public static Task<DotNetCliResult> ShutdownBuildServersAsync(string workingDirectory) =>
            RunAsync(workingDirectory, "build-server", "shutdown");

        public static Task<DotNetCliResult> BuildAsync(string projectDirectory, bool sharedCompilation, params string[] extraArguments)
        {
            var arguments = new List<string>
            {
                "build",
                "--nologo",
                "-c", TestPaths.Configuration,
                $"-p:CodegenCSSourceGeneratorPath={TestPaths.SourceGeneratorDir.TrimEnd('/', '\\')}/",
                $"-p:UseSharedCompilation={sharedCompilation.ToString().ToLowerInvariant()}",
                "-v:minimal",
            };
            arguments.AddRange(extraArguments);
            return RunAsync(projectDirectory, arguments.ToArray());
        }
    }
}
