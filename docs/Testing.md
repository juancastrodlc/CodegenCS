# Testing

All test projects are built and executed by [`src/run-tests.ps1`](../src/run-tests.ps1), which writes TRX reports to `src/artifacts/test-results/` and a Markdown summary to `src/artifacts/test-summary.md`.

```powershell
cd src
pwsh ./build.ps1                 # builds and packs the libraries into ./packages-local and installs dotnet-codegencs
pwsh ./run-tests.ps1             # templates/models are downloaded from GitHub
pwsh ./run-tests.ps1 -Offline    # templates/models are read from ./artifacts/OnlineTemplates
pwsh ./run-tests.ps1 -TemplatesUri <uri-or-folder>
```

On Linux the tests run from `CodegenCS.slnf` (Visual Studio extensions are excluded); on Windows from `CodegenCS.slnx`.

## Test projects

| Project | What it covers |
| --- | --- |
| `Core/CodegenCS.Tests` | Core library (writers, indentation, interpolation, symbols, models) |
| `Tools/Tests` | TemplateBuilder / TemplateLauncher (build and run templates in-process) |
| `Tools/CodegenCS.Tools.CliTool.Tests` | `dotnet-codegencs` CLI end-to-end (clone, build, run templates from the CodegenCS Templates catalog) |
| `SourceGenerator/SourceGenerator.Tests/SourceGenerator1.Tests` | Source Generator, based on [Samples/SourceGenerator1](../Samples/SourceGenerator1) (File/Memory outputs, Roslyn-aware templates, diagnostics, incremental caching, real `dotnet build`) |
| `SourceGenerator/SourceGenerator.Tests/SourceGenerator2.Tests` | Source Generator, based on [Samples/SourceGenerator2](../Samples/SourceGenerator2) (POCOs generated from a **SQLite** schema, queried with Dapper + Microsoft.Data.Sqlite) |

The source generator tests copy their `BaseProject` folder (a copy of the corresponding sample) into a temporary folder and exercise it in two ways:

- **In-process**: the generator is executed through Roslyn's `CSharpGeneratorDriver` and the output compilation is verified (and for SourceGenerator2 emitted and executed against an in-memory SQLite database).
- **Integration** (`[Category("Integration")]`): the base project is compiled with `dotnet build`, which runs the generator inside the real SDK compiler (`csc`, and also the shared compiler server `VBCSCompiler`). These tests are what catch problems like `CS9057` (the compiler silently refusing a generator that references a newer `Microsoft.CodeAnalysis`), assembly-loading issues inside the compiler's isolated `AssemblyLoadContext`, or a `File` output that is not part of the first build. The in-process tests alone cannot detect any of these, and that is why the original generator failures went unnoticed.

## Online sources and offline runs

Some tests depend on online resources:

- the [CodegenCS Templates](https://github.com/CodegenCS/Templates) catalog (`templates-index.json`) and templates (`SimplePocos`, `DapperExtensionPocos`, `DapperDalPocos`, `DapperActiveRecordPocos`, `NSwagClient`), cloned with `dotnet-codegencs template clone`;
- sample models (`AdventureWorksSchema.json`, `petstore-openapi3.json`).

The location of the Templates repository is defined by the environment variable **`CODEGENCS_TEMPLATES_URI`**:

| Value | Behavior |
| --- | --- |
| *(not defined)* | `https://raw.githubusercontent.com/CodegenCS/Templates/main/` (default, online) |
| another `http(s)://` URI | a mirror of the Templates repository |
| a local folder (or `file://` URI) | offline mirror. The folder may keep the repository structure (`DatabaseSchema/SimplePocos/SimplePocos.cs`) or be flat (`SimplePocos.cs`) |

The variable is honored both by the tests and by `dotnet-codegencs template clone` (so it also works outside the tests). In offline mode the sample models are read from the mirror folder and, if they are not there, from the copies kept in this repository (`src/Models/CodegenCS.Models.DbSchema.SampleDatabases/AdventureWorksSchema.json`, `src/Models/CodegenCS.Models.NSwagAdapter/SampleModels/petstore-openapi3.json`).

`src/artifacts/OnlineTemplates` contains the downloads required to run offline, so `run-tests.ps1 -Offline` is the same as:

```powershell
$env:CODEGENCS_TEMPLATES_URI = "$PWD/artifacts/OnlineTemplates"
pwsh ./run-tests.ps1
```

## Results

### Baseline (before the changes)

`CodegenCS.Tools.CliTool.Tests` failed completely in an offline environment (22 of 33 tests, all from `OneTimeSetUp` failing to reach GitHub), and there were no tests for the source generator at all.
The generator itself was broken: it couldn't be packed on Linux, couldn't be referenced as a project, and `dotnet build` silently ignored it (`warning CS9057`), so the samples didn't compile.

### After adding the source generator tests and fixing the generator (`ISourceGenerator`)

- **Result:** Passed
- **Configuration:** Debug
- **Solution:** CodegenCS.slnf
- **Templates source:** `src/artifacts/OnlineTemplates` (`run-tests.ps1 -Offline`)
- **Totals:** 196 passed, 0 failed, 0 skipped, 196 total (**100%**)

| Test report | Passed | Failed | Skipped | Total |
| --- | ---: | ---: | ---: | ---: |
| CodegenCS.Tests | 105 | 0 | 0 | 105 |
| CodegenCS.Tools.CliTool.Tests | 33 | 0 | 0 | 33 |
| CodegenCS.Tools.Tests | 36 | 0 | 0 | 36 |
| CodegenCS.SourceGenerator1.Tests | 15 | 0 | 0 | 15 |
| CodegenCS.SourceGenerator2.Tests | 7 | 0 | 0 | 7 |
| **Total** | **196** | **0** | **0** | **196** |

### Final run, after refactoring the generator to `IIncrementalGenerator`

Executed after `build.ps1` (clean build) and `build-samples.ps1` (packs the generator and compiles/runs every sample):

- **Result:** Passed
- **Configuration:** Debug
- **Solution:** CodegenCS.slnf
- **Templates source:** `src/artifacts/OnlineTemplates` (`run-tests.ps1 -Offline`)
- **Totals:** 203 passed, 0 failed, 0 skipped, 203 total (**100%**)

| Test report | Passed | Failed | Skipped | Total |
| --- | ---: | ---: | ---: | ---: |
| CodegenCS.Tests | 105 | 0 | 0 | 105 |
| CodegenCS.Tools.CliTool.Tests | 33 | 0 | 0 | 33 |
| CodegenCS.Tools.Tests | 36 | 0 | 0 | 36 |
| CodegenCS.SourceGenerator1.Tests | 20 | 0 | 0 | 20 |
| CodegenCS.SourceGenerator2.Tests | 9 | 0 | 0 | 9 |
| **Total** | **203** | **0** | **0** | **203** |

The 7 additional tests cover the incremental behavior (cached results on a rebuild without changes; source edits only re-running templates that use the `Compilation`; template edits only re-running that template; model edits re-running the template), `CSharpCompilation` injection and the `CODEGENCS004` migration diagnostic.
