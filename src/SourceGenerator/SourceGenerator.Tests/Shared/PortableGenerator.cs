using Microsoft.CodeAnalysis;
using System;
using System.IO;
using System.Reflection;
using System.Runtime.Loader;

namespace CodegenCS.SourceGenerator.Tests
{
    internal sealed class PortableGenerator : AssemblyLoadContext
    {
        private readonly string _directory;

        private PortableGenerator(string directory) : base(nameof(PortableGenerator) + Guid.NewGuid().ToString("N"))
        {
            _directory = directory;
        }

        public static ISourceGenerator Load()
        {
            var context = new PortableGenerator(TestPaths.PortableSourceGeneratorDir);
            var assembly = context.LoadFromAssemblyPath(Path.Combine(TestPaths.PortableSourceGeneratorDir, "CodegenCS.SourceGenerator.dll"));
            var generator = Activator.CreateInstance(assembly.GetType("CodegenCS.CodeGenerator.CodegenGenerator", throwOnError: true));
            return TestGenerator.Wrap(generator);
        }

        protected override Assembly Load(AssemblyName assemblyName)
        {
            if (assemblyName.Name.StartsWith("Microsoft.CodeAnalysis", StringComparison.Ordinal) ||
                assemblyName.Name is "System.Collections.Immutable" or "System.Reflection.Metadata")
                return null;
            var path = Path.Combine(_directory, assemblyName.Name + ".dll");
            return File.Exists(path) ? LoadFromAssemblyPath(path) : null;
        }
    }
}
