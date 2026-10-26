using System;
using System.IO;

namespace CodegenCS.SourceGenerator.Tests
{
    internal sealed class TestWorkspace : IDisposable
    {
        public string Directory { get; }

        private TestWorkspace(string directory)
        {
            Directory = directory;
        }

        public static TestWorkspace FromBaseProject()
        {
            var target = Path.Combine(Path.GetTempPath(), "CodegenCS.SourceGenerator.Tests", Guid.NewGuid().ToString("N"));
            CopyDirectory(TestPaths.BaseProjectDir, target);
            File.WriteAllText(Path.Combine(target, "NuGet.config"), $"""
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="packages-local" value="{TestPaths.PackagesLocalDir}" />
                  </packageSources>
                </configuration>
                """);
            File.WriteAllText(Path.Combine(target, "Directory.Build.props"), "<Project />");
            File.WriteAllText(Path.Combine(target, "Directory.Build.targets"), "<Project />");
            return new TestWorkspace(target);
        }

        public string PathOf(string relativePath) => Path.Combine(Directory, relativePath);

        public void Dispose()
        {
            try
            {
                System.IO.Directory.Delete(Directory, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        private static void CopyDirectory(string source, string target)
        {
            System.IO.Directory.CreateDirectory(target);
            foreach (var file in System.IO.Directory.GetFiles(source))
                File.Copy(file, Path.Combine(target, Path.GetFileName(file)));
            foreach (var dir in System.IO.Directory.GetDirectories(source))
            {
                var name = Path.GetFileName(dir);
                if (name is "bin" or "obj")
                    continue;
                CopyDirectory(dir, Path.Combine(target, name));
            }
        }
    }
}
