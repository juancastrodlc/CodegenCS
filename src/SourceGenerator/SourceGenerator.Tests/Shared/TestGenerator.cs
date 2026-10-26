using Microsoft.CodeAnalysis;

namespace CodegenCS.SourceGenerator.Tests
{
    internal static class TestGenerator
    {
        public static ISourceGenerator Create() => Wrap(new CodegenCS.CodeGenerator.CodegenGenerator());

        public static ISourceGenerator Wrap(object generator) => ((IIncrementalGenerator)generator).AsSourceGenerator();
    }
}
