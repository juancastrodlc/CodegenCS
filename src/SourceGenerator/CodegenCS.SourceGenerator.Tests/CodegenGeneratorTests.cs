using System.Diagnostics;
using System.Text.RegularExpressions;
using Xunit;

namespace CodegenCS.SourceGenerator.Tests;

/// <summary>
/// Integration tests for CodegenCS Source Generator
/// These tests use the actual build process to exercise the generator
/// </summary>
public class CodegenGeneratorIntegrationTests
{
    private readonly string _samplesPath;
    private readonly string _configuration;

    public CodegenGeneratorIntegrationTests()
    {
        // Navigate to the Samples directory from the test project
        var testDir = Directory.GetCurrentDirectory();
        var repoRoot = FindRepoRoot(testDir);
        _samplesPath = Path.Combine(repoRoot, "Samples");
        _configuration = "Debug";
    }

    [Fact]
    public void SourceGenerator1_BuildSucceeds_OnCurrentPlatform()
    {
        // Arrange
        var projectPath = Path.Combine(_samplesPath, "SourceGenerator1", "SourceGenerator1.csproj");
        Assert.True(File.Exists(projectPath), $"Sample project not found at {projectPath}");

        // Act
        var (exitCode, output) = RunDotNetBuild(projectPath);

        // Assert - Should succeed on all platforms once bug is fixed
        Assert.Equal(0, exitCode);
        Assert.Contains("Build succeeded", output);
    }

    [Fact]
    public void SourceGenerator1_GeneratesExpectedFiles_OnAllPlatforms()
    {
        // Arrange
        var projectPath = Path.Combine(_samplesPath, "SourceGenerator1", "SourceGenerator1.csproj");
        var projectDir = Path.GetDirectoryName(projectPath)!;
        
        // Clean previous generated files
        var generatedFiles = Directory.GetFiles(projectDir, "*.g.cs");
        foreach (var file in generatedFiles)
        {
            File.Delete(file);
        }

        // Act
        var (exitCode, output) = RunDotNetBuild(projectPath);

        // Assert - Should work on all platforms once bug is fixed
        Assert.Equal(0, exitCode);
        
        // Template1 generates to file
        var template1Output = Path.Combine(projectDir, "Template1.g.cs");
        Assert.True(File.Exists(template1Output), $"Template1 should generate {template1Output}");
        
        // Template2 and Template3 generate to memory only (no files)
        var template2Output = Path.Combine(projectDir, "Template2.g.cs");
        var template3Output = Path.Combine(projectDir, "Template3.g.cs");
        Assert.False(File.Exists(template2Output), "Template2 should generate to memory only");
        Assert.False(File.Exists(template3Output), "Template3 should generate to memory only");
    }

    [Fact]
    public void SourceGenerator_TemplatePathShouldNotBeEmpty()
    {
        // Test that template.Path is populated correctly on all platforms
        // Previously failed on Linux/macOS where AdditionalText.Path returned empty string
        
        var projectPath = Path.Combine(_samplesPath, "SourceGenerator1", "SourceGenerator1.csproj");
        var (exitCode, output) = RunDotNetBuild(projectPath);

        // Build should succeed - template.Path should be populated
        Assert.Equal(0, exitCode);
        Assert.DoesNotContain("The value cannot be an empty string", output);
        Assert.DoesNotContain("Parameter 'path'", output);
        
        // If this test fails with "empty string" error, it indicates:
        // CodegenGenerator.cs line 86: new FileInfo(template.Path).Directory.FullName
        // is receiving an empty template.Path (Roslyn bug on Linux/macOS)
    }

    #region Helper Methods

    private static string FindRepoRoot(string startPath)
    {
        var dir = new DirectoryInfo(startPath);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, ".git", "config")))
        {
            dir = dir.Parent;
        }
        
        if (dir == null)
        {
            throw new DirectoryNotFoundException("Could not find repository root");
        }
        
        return dir.FullName;
    }

    private (int exitCode, string output) RunDotNetBuild(string projectPath)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"build \"{projectPath}\" /p:Configuration={_configuration} /verbosity:minimal",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(startInfo);
        Assert.NotNull(process);

        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        var combinedOutput = output + "\n" + error;
        return (process.ExitCode, combinedOutput);
    }

    #endregion
}
