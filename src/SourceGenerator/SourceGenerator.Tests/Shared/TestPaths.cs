using System;
using System.IO;
using System.Linq;
using System.Reflection;

namespace CodegenCS.SourceGenerator.Tests
{
    internal static class TestPaths
    {
        private static string Metadata(string key) =>
            typeof(TestPaths).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>().Single(a => a.Key == key).Value;

        public static string SourceGeneratorDir => Metadata("CodegenCS.SourceGeneratorDir");

        public static string PortableSourceGeneratorDir => Metadata("CodegenCS.PortableSourceGeneratorDir");

        public static string PackagesLocalDir => Metadata("CodegenCS.PackagesLocalDir");

        public static string Configuration => Metadata("CodegenCS.Configuration");

        public static string BaseProjectDir => Path.Combine(AppContext.BaseDirectory, "BaseProject");
    }
}
