# CodegenCS.SourceGenerator.Tests

Integration tests for the CodegenCS Source Generator that exercise the generator through actual build processes.

## Running Tests

```bash
cd src
dotnet test SourceGenerator/CodegenCS.SourceGenerator.Tests/CodegenCS.SourceGenerator.Tests.csproj
```

Or with VS Code:
- Install .NET Core Test Explorer extension (optional)
- Tests will appear in the Testing sidebar
- Click "Run All Tests" or run individual tests

## Test Approach

Since source generators have complex dependency loading requirements (all dependencies must be packed into the analyzer directory), these tests use an **integration testing** approach rather than unit testing:

1. Tests invoke the actual `dotnet build` command
2. Build process exercises the source generator naturally
3. Tests verify output, exit codes, and generated files

This approach:
- ✅ Tests the generator in its real execution environment
- ✅ Works cross-platform (Linux/macOS/Windows)
- ✅ Avoids complex dependency loading issues
- ✅ Documents known platform-specific bugs

## Test Structure

- **CodegenGeneratorIntegrationTests.cs**: Integration test fixture
- **TestTemplates/**: Sample templates (not currently used, tests use Samples/SourceGenerator1)

## Key Test Scenarios

1. **SourceGenerator1_BuildSucceeds_OnCurrentPlatform**
   - Verifies successful build on all platforms
   - **Will FAIL on Linux/macOS** until bug is fixed

2. **SourceGenerator1_GeneratesExpectedFiles_OnAllPlatforms**
   - Verifies Template1.csx generates file output (`.g.cs`)
   - Verifies Template2/3.csx use memory mode (no files)
   - **Will FAIL on Linux/macOS** until bug is fixed

3. **SourceGenerator_TemplatePathShouldNotBeEmpty**
   - Verifies `template.Path` is populated correctly
   - **Will FAIL on Linux/macOS** until bug is fixed
   - Exposes the known issue where `AdditionalText.Path` returns empty string

## Known Issues

### Linux/macOS: Empty template.Path (BUG TO FIX)

On Linux and macOS, Roslyn's `AdditionalText.Path` returns an empty string, causing:
```
error CODEGENCS003: Failed to run CodegenCS Template '': 'The value cannot be an empty string. (Parameter 'path')'
```

**Root Cause**: `CodegenGenerator.cs` line 86:
```csharp
_executionFolder = new FileInfo(template.Path).Directory.FullName;
```

**Fix Required**:
- Add validation for empty `template.Path` before using it
- Use alternative approach to get template directory (e.g., from project metadata)
- Or use `GetText().ToString()` and parse file path from metadata

**Tests are NOW configured to FAIL** to expose this bug and drive the fix.

## Debugging Tests

In VS Code:
1. Open Test Explorer (beaker icon in sidebar)
2. Set breakpoints in test methods
3. Right-click test → "Debug Test"
4. Or use F5 with launch configuration

For debugging the actual source generator:
- See main README.md for `Debugger.Launch()` approach
- Or enable `EmitCompilerGeneratedFiles` in the generator's csproj

## Expected Test Results

Windows: All tests should PASS ✅
Linux/macOS: All tests should FAIL ❌ (exposing the bug)
