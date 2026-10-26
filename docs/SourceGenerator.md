# CodegenCS Source Generator

[CodegenCS.SourceGenerator](https://nuget.org/packages/CodegenCS.SourceGenerator) is a Roslyn **incremental source generator** (`IIncrementalGenerator`) that runs CodegenCS templates during compilation.
You only write templates: the generator builds and runs them for you, and adds their output to the compilation (in-memory) or saves it to disk.

- Templates are regular CodegenCS templates (same entry points, subtemplates, indent control, dependency injection, models, etc).
- Templates can read the code being compiled (Roslyn `Compilation`), so they can augment existing classes.
- Incremental: a template only runs again when its inputs change.

## Quickstart

1. Add the package to your project:

   ```xml
   <ItemGroup>
     <PackageReference Include="CodegenCS.SourceGenerator" Version="3.5.2" />
   </ItemGroup>
   ```

2. Create a template, e.g. `MyTemplate.csx`:

   ```cs
   class MyTemplate
   {
       void Main(ICodegenContext context)
       {
           context["MyClass1.g.cs"].Write($$"""
               public class MyClass1
               {
               }
               """);
       }
   }
   ```

3. Register the template as `AdditionalFiles` and choose where the output goes with the `CodegenCSOutput` metadata:

   ```xml
   <ItemGroup>
     <AdditionalFiles Include="MyTemplate.csx" CodegenCSOutput="Memory" />
     <!-- "Memory": output is added to the compilation only. "File": output is also saved next to the template -->
   </ItemGroup>
   ```

   The package declares `<CompilerVisibleItemMetadata Include="AdditionalFiles" MetadataName="CodegenCSOutput" />` automatically (declaring it again in your project is harmless).

4. Build. `MyClass1` is now part of your project.

See [Samples/SourceGenerator1](../Samples/SourceGenerator1) (templates with File/Memory outputs and a template that augments partial classes) and [Samples/SourceGenerator2](../Samples/SourceGenerator2) (POCOs generated from a SQLite database schema and queried with Dapper).

## Which files are templates?

An `AdditionalFiles` item is executed as a template when:

- its extension is `.csx`, `.cs` or `.cgcs`, **and**
- it defines `CodegenCSOutput` (`Memory` or `File`, case-insensitive). Any other value reports `CODEGENCS003`.

Every other `AdditionalFiles` item is ignored by the generator, except that it's tracked as a dependency (see [Models](#models-and-other-dependencies)).

## Outputs

The default output file of a template is `<TemplateName>.g.cs`; templates can write as many files as they want (`context["Other.g.cs"]`).
Generated sources are added to the compilation using the file's relative path as hint name (folder separators become `.`).

| `CodegenCSOutput` | Behavior |
| --- | --- |
| `Memory` | Output is added to the compilation (in-memory), nothing is written to disk. If a file with the same name was previously generated with `File` it's deleted. |
| `File` | Output is saved to disk (relative to the template folder). If the file is not yet part of the compilation (e.g. on a clean build, since the project items are evaluated before the template runs) it's also added in-memory, so the very first build already compiles. On the following builds the file on disk is compiled normally and it's not added again (no duplicate types). Files are only rewritten when their contents change. |

## Templates that read the code being compiled

Templates can receive the Roslyn compilation through dependency injection, just like any other type:

```cs
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp.Syntax;

class Template3
{
    void Main(ICodegenContext context, Compilation compilation)
    {
        var classes = compilation.SyntaxTrees
            .SelectMany(syntaxTree => syntaxTree.GetRoot().DescendantNodes())
            .OfType<ClassDeclarationSyntax>();
        foreach (var c in classes)
        {
            var symbol = compilation.GetSemanticModel(c.SyntaxTree).GetDeclaredSymbol(c);
            context[$"{symbol.Name}.g.cs"].Write($$"""
                namespace {{symbol.ContainingNamespace.ToDisplayString()}}
                {
                    partial class {{symbol.Name}}
                    {
                        public void Initialize() { }
                    }
                }
                """);
        }
    }
}
```

Both `Microsoft.CodeAnalysis.Compilation` and `Microsoft.CodeAnalysis.CSharp.CSharpCompilation` can be injected. Full example: [Samples/SourceGenerator1/Template3.csx](../Samples/SourceGenerator1/Template3.csx).

### Migrating from previous versions (`GeneratorExecutionContext`)

Previous versions were based on `ISourceGenerator` and injected `GeneratorExecutionContext`. That type doesn't exist in incremental generators, so templates that use it report **`CODEGENCS004`**. Replace the parameter with `Compilation`:

```diff
- void Main(ICodegenContext context, GeneratorExecutionContext generatorContext)
+ void Main(ICodegenContext context, Compilation compilation)
  {
-     var trees = generatorContext.Compilation.SyntaxTrees;
+     var trees = compilation.SyntaxTrees;
```

## Models and other dependencies

Templates can load models with `IModelFactory` (paths are relative to the template folder):

```cs
public void Main(ICodegenContext context, IModelFactory factory)
{
    var schema = factory.LoadModelFromFile<DatabaseSchema>("AdventureWorksSchema.json");
    ...
}
```

Models are read from disk by the template, so Roslyn doesn't know about them. To have the templates run again when a model changes, list the model as `AdditionalFiles` **without** `CodegenCSOutput`:

```xml
<AdditionalFiles Include="SimplePOCOGenerator.csx" CodegenCSOutput="Memory" />
<AdditionalFiles Include="AdventureWorksSchema.json" />
```

## Incremental behavior

The generator is built on `IIncrementalGenerator`, and every pipeline value is value-equatable, so Roslyn caches the result of each template:

| Change | Templates that run again |
| --- | --- |
| Nothing (e.g. a design-time build or a build with no changes) | none |
| A template file (contents or `CodegenCSOutput`) | only that template |
| A dependency (`AdditionalFiles` without `CodegenCSOutput`, e.g. a model) | all templates |
| Source code (any `.cs` in the project) | only templates that use the compilation |

A template "uses the compilation" when its source mentions `Microsoft.CodeAnalysis` or `Compilation`/`CSharpCompilation`. Other templates never depend on the C# code, which keeps IDE typing fast.

In addition, compiled templates are cached by content (template text + generator version), so a template that runs again because the compilation changed is not recompiled.

The pipeline steps are exposed through tracking names (`CodegenGenerator.TemplatesTrackingName`, `DependenciesTrackingName`, `RunTemplateTrackingName`, `RunCompilationAwareTemplateTrackingName`), which are used by the tests to assert caching (`GeneratorDriverOptions(trackIncrementalGeneratorSteps: true)`).

## Diagnostics

| Id | Severity | Meaning |
| --- | --- | --- |
| `CODEGENCS001` | Error | The template failed to build (no line information) |
| `CODEGENCS002` | Error | The template failed to build. The diagnostic points to the template file, line and column |
| `CODEGENCS003` | Error | The template failed to run (exception, template errors, invalid `CodegenCSOutput`, output file could not be written) |
| `CODEGENCS004` | Error | The template uses `GeneratorExecutionContext` (see [Migrating](#migrating-from-previous-versions-generatorexecutioncontext)) |

Template failures don't stop other templates from running.

## Compatibility and package layout

The C# compiler refuses (only with a warning, `CS9057`) any analyzer that references a newer `Microsoft.CodeAnalysis` than itself, so a generator built against a recent Roslyn package silently does nothing in older SDKs/IDEs. This was the main reason the previous version of the generator "did nothing" with the .NET 10 SDK (Roslyn 5.0), as it was built against Microsoft.CodeAnalysis 5.9.

The package therefore uses Roslyn-versioned analyzer folders, and the .NET SDK picks the highest one that is not newer than the compiler running the build:

| Folder | Build |
| --- | --- |
| `analyzers/dotnet/roslyn5.9/cs` | `netstandard2.0`, compiled against the `Microsoft.CodeAnalysis.CSharp` 5.9 package (portable, for compilers with Roslyn 5.9+) |
| `analyzers/dotnet/roslynX.Y/cs` | compiled against the Roslyn assemblies of the .NET SDK that built the package (`$(RoslynTargetsPath)/bincore`, `$(CompilerApiVersion)`, e.g. `roslyn5.0` for the .NET 10 SDK) and targeting that SDK's runtime |

Both builds contain the generator and all its dependencies (CodegenCS libraries, Newtonsoft.Json, NJsonSchema, NSwag, System.CommandLine, ...). Assemblies provided by the compiler (Microsoft.CodeAnalysis, System.Collections.Immutable, System.Reflection.Metadata, ...) are never packed. The package has no NuGet dependencies and is a development dependency.

Notes:

- Inside the compiler, analyzers are isolated in their own `AssemblyLoadContext` (and the compiler server `VBCSCompiler` loads them from memory). The generator loads the compiled templates into that same context and resolves template references from the original analyzer folder, so templates see the very same CodegenCS types as the generator.
- The generator doesn't depend on SQL Server client libraries (the template tools are compiled into the generator assembly without their SqlClient/Npgsql/Dapper dependencies). Templates that need those can reference them with `#r`.
- The `roslynX.Y` build targets the SDK runtime (e.g. `net10.0`), so it's meant for `dotnet build`/`csc` on .NET. Hosts running on .NET Framework (Visual Studio) need a compiler with Roslyn 5.9+ to use the portable build.
- Template executions are serialized within a process, because the template runner temporarily changes the current directory to the template folder.

## Building and testing locally

From the `src` folder:

```powershell
pwsh ./build-sourcegenerator.ps1        # builds and packs CodegenCS.SourceGenerator into ./packages-local, then compiles the source generator samples
pwsh ./build-samples.ps1                # packs the generator and compiles every sample in ../Samples/Samples.slnx (PrebuildEvent requires ./build-tools.ps1 first)
pwsh ./build-samples.ps1 -SkipPack -Projects SourceGenerator1,SourceGenerator2
pwsh ./run-tests.ps1 -Offline           # runs every test, reading online templates from ./artifacts/OnlineTemplates
```

`build-samples.ps1` rebuilds the samples from scratch, fails if the compiler reports any generator problem (`CS9057`, `CS8032`-`CS8034`, `CS8784`, `CS8785` or `CODEGENCS*`), checks that the `File` output of `SourceGenerator1/Template1.csx` was generated, and runs `SourceGenerator2` (which creates an in-memory SQLite database and queries it with the generated POCOs).

To consume a local build of the generator without packing it (as the tests do), reference the build output folder as analyzers:

```xml
<ItemGroup>
  <Analyzer Include="path/to/src/SourceGenerator/CodegenCS.SourceGenerator/bin/Debug/net10.0/*.dll" />
  <CompilerVisibleItemMetadata Include="AdditionalFiles" MetadataName="CodegenCSOutput" />
</ItemGroup>
```

After rebuilding the generator, run `dotnet build-server shutdown` so the compiler server doesn't keep the previous version loaded.

The tests are in `src/SourceGenerator/SourceGenerator.Tests` (one test project per sample, plus shared helpers). Each test copies its `BaseProject` (a copy of the sample) to a temporary folder and runs the generator both in-process (`CSharpGeneratorDriver`) and through `dotnet build` with the real SDK compiler. See [Testing](Testing.md).

## Debugging

`IsRoslynComponent` is enabled in the project, so in Visual Studio you can create a launch profile of type "Roslyn Component" targeting a project that uses the generator.
The incremental pipeline can be inspected with `GeneratorDriverOptions(IncrementalGeneratorOutputKind.None, trackIncrementalGeneratorSteps: true)`, as in the tests (`GeneratorHarness`).
