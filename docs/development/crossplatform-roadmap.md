# Cross-Platform Development Roadmap

## Current Status

### ✅ Completed
- **Build Scripts**: Standardized PowerShell scripts with try-finally blocks and consolidated tool detection
- **Core Tests**: All passing on Linux
- **CLI Tool Tests**: Fixed for cross-platform executable names and line endings
- **Solution Filter**: Created `CodegenCS-Linux.slnf` to hide Windows-only projects
- **VS Code Configuration**: Configured to exclude Visual Studio extension projects on Linux

### 🔄 Known Issues Requiring Investigation

#### 1. Source Generator Integration Test Differences
**Problem**: Source Generator integration tests failing due to platform-specific build output differences

**Root Cause**: These are integration tests that invoke actual `dotnet build` commands and verify
real MSBuild/Roslyn behavior, which differs legitimately between platforms.

**Observations**:
- Tests require framework version in filenames (e.g., `net9.0/`) on Linux but not on Windows
- Build output paths differ: Linux uses `bin/Debug/net9.0/`, Windows may use different conventions
- Console output captures from Windows don't match Linux console output
- Additional diagnostic output appears on Linux that's not present in Windows
- Snapshot formatting differences between platforms (line endings, path separators)
- **Critical**: `AdditionalText.Path` property returns empty string on Linux/macOS (known Roslyn issue)

**Integration Test Nature**:
- These tests validate end-to-end workflows, not isolated units
- They depend on: .NET SDK, MSBuild, Roslyn, file system, sample projects
- Platform differences are expected and should be documented, not eliminated
- Failures may indicate issues in build configuration, not just code logic

**Action Items**:
- [ ] Compare test output on actual Windows machine vs Linux (need Windows access, possibly mitigated with Testably.Abstractions)
- [ ] Create platform-specific snapshot baselines (separate for Windows/Linux/macOS)
- [ ] Add platform detection helpers to integration test base class
- [ ] Document expected platform-specific output differences in test comments
- [ ] Consider using `[Platform]` NUnit attribute to skip platform-specific tests
- [ ] Investigate Roslyn `AdditionalText.Path` empty string issue on Linux/macOS
- [ ] Add integration test documentation explaining platform behavior expectations

#### 2. Console Output Formatting
**Problem**: Line endings and formatting differ between platforms

**Status**:
- Partially fixed by using `Environment.NewLine` in assertions
- Some snapshot tests still need updating

**Action Items**:
- [ ] Audit all snapshot tests for platform-specific formatting
- [ ] Create normalized comparison helpers for cross-platform tests
- [ ] Document which tests are expected to have platform-specific snapshots

#### 3. File Path Handling
**Problem**: Some tests hard-code Windows path separators or .exe extensions

**Status**:
- Fixed in `BaseTest.cs` for CLI tool executable names
- May exist in other test files

**Action Items**:
- [ ] Grep for hard-coded `.exe` references
- [ ] Grep for hard-coded `\` path separators
- [ ] Create cross-platform path helper utilities

### 🚫 Not Supported (Windows-Only)
- **Visual Studio Extensions**: `VS2019Extension, VS2022Extension, CodegenCS.Runtime.VisualStudio`
- **.NET Framework projects**: Projects targeting `net4xx` frameworks
- **NuGet Package Explorer**: Windows-only GUI tool (optional dev dependency)

## Platform-Specific Behaviors

### Linux
- Uses symlink-aware path resolution in build scripts
- Requires 7z (p7zip-full) for archive operations
- Uses `ilspycmd` for decompilation (cross-platform alternative to `dnSpy`)
- Line endings: `LF` (`\n`)
- Executable names: No `.exe` extension

### Windows
- Direct path resolution
- Uses 7-Zip from Program Files
- Uses `dnSpy` for decompilation, considering using `ilspycmd` as it is already cross-platform.
- Line endings: CRLF (`\r\n`)
- Executable names: `.exe` extension required

## Testing Strategy

### Test Classification

#### Unit Tests
**`CodegenCS.Tests`** (Core unit tests)
- **Status**: ✅ All passing on Linux
- **Type**: Unit tests - isolated, fast, no external dependencies
- **Approach**: Platform-agnostic code generation tests
- **Execution**: Run on every build, ~milliseconds
- **Dependencies**: None (pure in-memory operations)

#### Integration Tests
**`CodegenCS.SourceGenerator.Tests`** (Source Generator integration tests)
- **Status**: ⚠️ Needs investigation
- **Type**: Integration tests - validates full Roslyn pipeline
- **Approach**:
  - Uses `dotnet build` to compile actual sample projects
  - Launches full Roslyn source generator pipeline
  - Tests cross-platform file I/O behavior
  - Validates generated code compilation
- **Execution**: Slower (~seconds per test), run separately in CI/CD
- **Dependencies**:
  - Built `CodegenCS.SourceGenerator` package
  - Sample projects in `/Samples/SourceGenerator1`
  - .NET SDK and MSBuild
- **Issues**:
  - Framework version in output paths (net9.0 vs platform-specific)
  - Console output format differences between platforms
  - Snapshot mismatches due to platform-specific behavior
  - Template.Path may be empty on Linux/macOS (Roslyn bug)
- **Cross-Platform Concerns**:
  - File path conventions differ (\ vs /)
  - Build output locations vary by platform
  - Diagnostic message formatting differences

**CodegenCS.Tools.CliTool.Tests** (CLI Tool integration tests)
- **Status**: ✅ Fixed for cross-platform
- **Type**: Integration tests - validates full CLI workflow
- **Approach**:
  - Uses `CliWrap` to execute `dotnet-codegencs` as external process
  - Tests download → build → run template workflow
  - Makes network calls (downloads templates from GitHub)
  - Tests cross-platform executable naming and process spawning
- **Execution**: Slower (~seconds per test), requires network
- **Dependencies**:
  - Built `dotnet-codegencs` executable
  - Network access for template downloads
  - File system permissions for temp directories
  - Cross-platform environment variables (TMPDIR, TMP, TEMP)
- **Cross-Platform Fixes Applied**:
  - Platform-specific executable name detection (`.exe` on Windows)
  - `Environment.NewLine` for line ending assertions
  - Normalized output comparison
  - Executable path resolution in `BaseTest.cs`
- **Test Categories**:
  - Basic CLI commands (help, version)
  - Template clone operations (by alias, URL, short URL)
  - Template build and execution
  - Model extraction and processing
  - Error handling and validation

### Integration Test Organization

**Prerequisites for Running Integration Tests**:
1. Built executables must be available:
   - `dotnet-codegencs` (for CLI tests)
   - `CodegenCS.SourceGenerator.dll` (for source generator tests)
2. Sample projects must be present (`/Samples` directory)
3. Network access (for CLI template download tests)
4. Sufficient file system permissions for temp operations
5. Platform-specific tools:
   - Windows: Standard .NET SDK
   - Linux: .NET SDK + proper temp directory configuration

**Recommended Test Categories** (NUnit):
```csharp
[Test]
[Category("Integration")]
public void SourceGenerator1_BuildSucceeds_OnCurrentPlatform() { }

[Test]
[Category("Integration")]
[Category("RequiresNetwork")]
public async Task CloneByFullUrl() { }

[Test]
[Category("Integration")]
[Category("RequiresBuild")]
public void SourceGenerator_GeneratesExpectedFiles() { }
```

**CI/CD Pipeline Structure**:
```
├── Stage 1: Build
│   ├── Compile all projects
│   └── Package CodegenCS.SourceGenerator
├── Stage 2: Unit Tests
│   ├── CodegenCS.Tests
│   ├── Fast execution (~seconds total)
│   └── No external dependencies
├── Stage 3: Integration Tests
│   ├── SourceGenerator.Tests (requires build artifacts)
│   ├── CliTool.Tests (requires network + build artifacts)
│   ├── Longer timeouts (~minutes)
│   └── Platform-specific matrix (Windows, Linux, macOS)
└── Stage 4: Cross-Platform Validation
    ├── Compare outputs across platforms
    ├── Validate snapshot differences
    └── Document platform-specific behavior
```

**Failure Diagnosis**:
- **Unit test failure**: Logic bug in core code generation
- **Integration test failure**: Could indicate:
  - Build system configuration issues
  - Platform-specific runtime bugs
  - Network/infrastructure problems (CliTool tests)
  - Roslyn API behavior differences (SourceGenerator tests)
  - Environment configuration issues (paths, temp dirs)
  - Regression in end-to-end workflow

**Test Isolation**:
- Each integration test should use unique temp directories
- Clean up generated files after test execution
- Avoid shared state between tests
- Use test fixtures for expensive setup (e.g., building executables once)

### Action Items for Integration Tests
- [ ] Add `[Category("Integration")]` attributes to SourceGenerator and CliTool tests
- [ ] Add `[Category("RequiresNetwork")]` to CLI download tests
- [ ] Configure CI/CD to run integration tests separately with longer timeouts
- [ ] Document prerequisites for running integration tests locally
- [ ] Create test fixtures to share expensive setup (building executables)
- [ ] Add platform-specific snapshot comparison helpers
- [ ] Investigate SourceGenerator.Tests platform differences systematically
- [ ] Consider adding smoke tests that run on every commit (subset of integration tests)

## Development Workflow

### Setting Up Linux Development Environment
1. Clone repository
2. Open `src/CodegenCS-Linux.slnf` in VS Code
3. Install dependencies:
   ```bash
   sudo apt install p7zip-full
   dotnet tool install -g ilspycmd
   ```
4. Run build: `./src/build.ps1`

### Testing Cross-Platform Changes

**Quick Local Testing** (Unit tests only):
```bash
# Run fast unit tests only
dotnet test src/CodegenCS.sln --filter "TestCategory!=Integration"
```

**Full Local Testing** (Unit + Integration tests):
```bash
# Run all tests including integration tests
dotnet test src/CodegenCS.sln

# Or run specific test projects
dotnet test src/Core/CodegenCS.Tests                          # Unit tests (fast)
dotnet test src/SourceGenerator/CodegenCS.SourceGenerator.Tests  # Integration (slow)
dotnet test src/Tools/CodegenCS.Tools.CliTool.Tests           # Integration (slow, needs network)
```

**Integration Test Requirements**:
- Ensure build has completed successfully first
- Network access required for CliTool tests
- Sufficient disk space for temp files
- May take several minutes to complete

**Cross-Platform Verification**:
1. Test on Linux: `dotnet test src/CodegenCS.sln`
2. Verify Windows compatibility (when available):
   - Test on actual Windows machine, mock through `Testably.Abstractions` when not
   - Compare snapshot outputs (expected to differ for some tests)
   - Document any intentional platform differences
3. Review integration test results:
   - `SourceGenerator` tests: Check build output paths
   - `CliTool` tests: Verify executable naming and line endings
1. Update snapshots if platform differences are intentional

### Committing Changes
- Include cross-platform fixes in commit messages
- Update this roadmap with progress
- Document new platform-specific behaviors discovered
- Update integration test snapshots if platform differences are expected
- Add `[Platform]` attributes to tests that are platform-specific

### CI/CD Configuration

**Recommended GitHub Actions Workflow**:

```yaml
name: CI/CD

on: [push, pull_request]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
        # macOS can be added later: macos-latest
    runs-on: ${{ matrix.os }}
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '9.0.x'
      
      - name: Install Linux dependencies
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y p7zip-full
          dotnet tool install -g ilspycmd
      
      - name: Build
        run: dotnet build src/CodegenCS.sln --configuration Release
      
      - name: Unit Tests (Fast)
        run: dotnet test src/Core/CodegenCS.Tests --configuration Release --logger "trx;LogFileName=unit-tests.trx"
        
      - name: Integration Tests - SourceGenerator
        run: dotnet test src/SourceGenerator/CodegenCS.SourceGenerator.Tests --configuration Release --logger "trx;LogFileName=sg-integration-tests.trx"
        timeout-minutes: 10
        
      - name: Integration Tests - CLI Tool
        run: dotnet test src/Tools/CodegenCS.Tools.CliTool.Tests --configuration Release --logger "trx;LogFileName=cli-integration-tests.trx"
        timeout-minutes: 15
        env:
          # Ensure temp directories are configured
          TMPDIR: ${{ runner.temp }}
          TMP: ${{ runner.temp }}
          TEMP: ${{ runner.temp }}
      
      - name: Publish Test Results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: '**/TestResults/*.trx'
          check_name: 'Test Results (${{ matrix.os }})'
      
      - name: Upload Build Artifacts
        if: runner.os == 'Linux'
        uses: actions/upload-artifact@v4
        with:
          name: packages
          path: |
            **/*.nupkg
            **/*.snupkg

  cross-platform-validation:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Compare Platform Results
        run: echo "Add logic to compare test outputs across platforms"
        # Could download artifacts from both platforms and compare
```

**Key CI/CD Considerations**:
- **Separate test stages**: Unit tests run first (fast feedback), then integration tests
- **Longer timeouts**: Integration tests need 10-15 minutes vs 1-2 minutes for unit tests
- **Platform matrix**: Run on both Windows and Linux (macOS future)
- **Environment variables**: Configure temp directories consistently
- **Artifact storage**: Keep test results and logs for debugging platform differences
- **Network access**: Ensure CliTool tests can download templates
- **Test result reporting**: Use platform-specific test result names for clarity

**Current Status**:
- [ ] CI/CD pipeline not yet configured
- [ ] Need to add GitHub Actions workflow
- [ ] Need to configure platform-specific test baselines
- [ ] Need to set up artifact comparison for cross-platform validation

## Future Enhancements

### Version Management
**Current State**: Manual versioning with hard-coded `<Version>` tags in each `.csproj` file
- Multiple inconsistent versions (3.5.0, 3.5.2, 3.1.3, 2.0.3)
- Must manually update each file during release
- No automated version bumping

**Recommended Solution**: [Nerdbank.GitVersioning (nbgv)](https://github.com/dotnet/Nerdbank.GitVersioning)

**Action Items**:
- [x] Install nbgv: `dotnet tool install -g nbgv` installed as tool invoked by `dotnet nbgv <args>`
- [x] Initialize in repository: `dotnet nbgv install`
- [x] Configure `version.json`:
  ```json
  {
    "$schema": "https://raw.githubusercontent.com/dotnet/Nerdbank.GitVersioning/master/src/NerdBank.GitVersioning/version.schema.json",
    "version": "4.0-alpha",
    "publicReleaseRefSpec": [
      "^refs/heads/master$",
      "^refs/tags/v\\d+\\.\\d+"
    ],
    "cloudBuild": {
      "buildNumber": {
        "enabled": true
      }
    }
  }
  ```
- [x] Remove hardcoded `<Version>` tags from .csproj files
- [x] Add `<PackageReference Include="Nerdbank.GitVersioning" />` to Directory.Build.props
- [ ] Test version generation: `nbgv get-version`
- [ ] Update build scripts to use nbgv-generated versions
- [ ] Document versioning strategy in repository

**Benefits**:
- Automatic semantic versioning from git history
- Consistent versions across all packages
- Build metadata includes commit SHA
- Preview/beta versions for non-release branches
- CI/CD friendly

### Testing Infrastructure

#### File System Abstraction with Testably.Abstractions
**Current Issues**:
- Tests use `System.IO.File`, `System.IO.Directory` directly
- Platform-specific path separators cause test failures
- Hardcoded paths don't work across platforms
- Difficult to mock file system in unit tests
- File system operations differ between Windows/Linux
- **Critical**: Cannot test Windows behavior on Linux (and vice versa)

**Solution**: [Testably.Abstractions](https://github.com/Testably/Testably.Abstractions)
- Provides `IFileSystem` abstraction over System.IO
- Drop-in replacement with minimal code changes
- Full mocking support for unit tests
- Cross-platform path handling built-in
- **Platform simulation**: Test Windows behavior on Linux and vice versa
- Same API as System.IO (easy migration)
- Battle-tested (3+ years, 15,000+ LOC)

**Decision**: Use Testably.Abstractions across entire project (production + tests)
- Rationale: Cross-platform behavior testing is essential for CodegenCS
- The ability to test Windows paths on Linux is critical for code generation consistency
- External dependency drawback is acceptable given the project's nature

**Implementation Plan**:
1. **Add Package References**
   ```bash
   # Production projects - Add Testably.Abstractions
   dotnet add src/Core/CodegenCS/CodegenCS.csproj package Testably.Abstractions
   dotnet add src/Core/CodegenCS.Runtime/CodegenCS.Runtime.csproj package Testably.Abstractions
   dotnet add src/Tools/CodegenCS.Tools.TemplateLauncher/CodegenCS.Tools.TemplateLauncher.csproj package Testably.Abstractions
   dotnet add src/Tools/CodegenCS.Tools.TemplateBuilder/CodegenCS.Tools.TemplateBuilder.csproj package Testably.Abstractions

   # Test projects - Add Testably.Abstractions.Testing
   dotnet add src/Core/CodegenCS.Tests/CodegenCS.Tests.csproj package Testably.Abstractions.Testing
   dotnet add src/Tools/CodegenCS.Tools.CliTool.Tests/CodegenCS.Tools.CliTool.Tests.csproj package Testably.Abstractions.Testing
   dotnet add src/SourceGenerator/CodegenCS.SourceGenerator.Tests/CodegenCS.SourceGenerator.Tests.csproj package Testably.Abstractions.Testing
   ```

2. **Refactor Production Code to Use IFileSystem**
   ```csharp
   // Add to constructors (optional parameter, defaults to real file system)
   public class TemplateLauncher
   {
       private readonly IFileSystem _fileSystem;
       
       public TemplateLauncher(/* existing params */, IFileSystem? fileSystem = null)
       {
           _fileSystem = fileSystem ?? new FileSystem();
       }
   }

   // Replace System.IO calls
   // Before:
   var content = File.ReadAllText(path);
   if (!Directory.Exists(outputDir))
       Directory.CreateDirectory(outputDir);
   File.WriteAllText(Path.Combine(outputDir, "output.cs"), content);

   // After:
   var content = _fileSystem.File.ReadAllText(path);
   if (!_fileSystem.Directory.Exists(outputDir))
       _fileSystem.Directory.CreateDirectory(outputDir);
   _fileSystem.File.WriteAllText(_fileSystem.Path.Combine(outputDir, "output.cs"), content);
   ```

3. **Update Test Base Classes**
   ```csharp
   // BaseTest.cs
   protected IFileSystem FileSystem { get; private set; }

   [SetUp]
   public void BaseSetUp()
   {
       FileSystem = new MockFileSystem(); // Use in-memory file system
   }
   ```

4. **Add Cross-Platform Test Cases**
   ```csharp
   [Test]
   public void TestWindowsBehaviorOnLinux()
   {
       var windowsFs = new MockFileSystem(o => o.SimulatingOperatingSystem(OSPlatform.Windows));
       var launcher = new TemplateLauncher(/* params */, windowsFs);
       
       windowsFs.File.WriteAllText(@"C:\Templates\template.csx", "content");
       launcher.Execute(@"C:\Templates\template.csx");
       
       // Test case-insensitive behavior
       Assert.That(windowsFs.File.Exists(@"C:\TEMPLATES\template.csx"), Is.True);
   }

   [Test]
   public void TestLinuxBehaviorOnWindows()
   {
       var linuxFs = new MockFileSystem(o => o.SimulatingOperatingSystem(OSPlatform.Linux));
       var launcher = new TemplateLauncher(/* params */, linuxFs);
       
       linuxFs.File.WriteAllText("/home/templates/template.csx", "content");
       launcher.Execute("/home/templates/template.csx");
       
       // Test case-sensitive behavior
       Assert.That(linuxFs.File.Exists("/home/TEMPLATES/template.csx"), Is.False);
   }
   ```

5. **Migration Strategy**
   - [ ] **Week 1**: Core libraries (CodegenCS, CodegenCS.Runtime)
   - [ ] **Week 1**: Update tests for core libraries
   - [ ] **Week 2**: Tools (TemplateLauncher, TemplateBuilder)
   - [ ] **Week 2**: Update tests with cross-platform cases
   - [ ] **Week 3**: Remaining projects (Models, etc.)
   - [ ] **Week 3**: Full test suite verification

6. **Benefits**
   - ✅ **Critical**: Test Windows behavior on Linux (and vice versa)
   - ✅ Tests run in-memory (10-100x faster)
   - ✅ No file system cleanup needed
   - ✅ Tests are isolated (no shared state)
   - ✅ Cross-platform path handling automatic
   - ✅ Easy to simulate file system errors
   - ✅ Consistent behavior in production code
   - ✅ Battle-tested implementation (3+ years)

**Priority Action Items**:
- [ ] Add Testably.Abstractions to production projects
- [ ] Add Testably.Abstractions.Testing to test projects
- [ ] Refactor core libraries to inject IFileSystem
- [ ] Refactor BaseTest.cs to use MockFileSystem
- [ ] Update failing tests with path issues first
- [ ] Add cross-platform test cases (Windows on Linux, Linux on Windows)
- [ ] Update hardcoded path separators in test assertions
- [ ] Migrate all file I/O operations systematically
- [ ] Add file system abstraction examples to docs
- [ ] Create helper methods for common file operations

#### General Testing Infrastructure
- [ ] Automate cross-platform testing in CI/CD (GitHub Actions)
- [ ] Create platform-specific snapshot baseline system
- [ ] Add platform detection in test helpers
- [ ] Normalize console output for comparison
- [ ] Consider .NET 8+ hosting model for truly cross-platform builds

### VS Code Extension Development
**Goal**: Create cross-platform VS Code extensions equivalent to VS2019/VS2022 extensions

#### Architecture Analysis
Current Visual Studio extensions:
- **VS2019Extension / VS2022Extension**: Visual Studio IDE integration
  - Template execution from Solution Explorer
  - Project integration
  - Output window integration
  - Windows-only (requires VS SDK)

- **CodegenCS.Runtime.VisualStudio**: Runtime support for VS integration
  - DTE integration (Visual Studio automation)
  - Solution/Project access
  - File system integration
  - Windows-only dependencies

#### VS Code Extension Plan

**Phase 1: Core Extension Structure**
- [ ] Create `src/VSCode/CodegenCS.VSCode.Extension/` project
- [ ] Set up TypeScript/JavaScript extension scaffold
- [ ] Configure extension manifest (package.json)
- [ ] Define activation events (solution opened, .csx files detected)
- [ ] Set up debugging configuration for extension development

**Phase 2: Runtime Abstraction Layer**
- [ ] Create `src/VSCode/CodegenCS.Runtime.VSCode/` (.NET project)
  - Cross-platform equivalent to CodegenCS.Runtime.VisualStudio
  - Workspace/folder access (vs. Solution/Project)
  - File system operations
  - Output channel integration
- [ ] Define common runtime interface for both VS and VS Code
- [ ] Implement Language Server Protocol (LSP) for .csx file support

**Phase 3: Core Features**
- [ ] **Template Execution**
  - Command palette commands for running templates
  - Context menu integration for .csx files
  - Template discovery in workspace
  - Progress reporting and cancellation

- [ ] **Workspace Integration**
  - Detect .NET solutions and projects
  - Template file associations
  - Configuration file support (CodegenCS.json)

- [ ] **Output & Diagnostics**
  - CodegenCS output channel
  - Error/warning reporting
  - Generated file tracking
  - Diff preview before writing

**Phase 4: Advanced Features**
- [ ] **IntelliSense for Templates**
  - C# script completion via OmniSharp/Roslyn
  - Template API code completion
  - Model schema validation

- [ ] **Template Management**
  - Template marketplace integration
  - Template download/install from CLI
  - Local template library

- [ ] **Multi-root Workspace Support**
  - Handle multiple solutions in one workspace
  - Per-folder configuration

**Phase 5: Platform-Specific Enhancements**
- [ ] **Linux-specific**
  - GTK file dialogs (if needed)
  - Linux path conventions
  - Shell integration

- [ ] **macOS-specific**
  - macOS path conventions
  - Finder integration

- [ ] **Windows-specific**
  - Optional Visual Studio interop (if VS installed)
  - Windows path conventions

#### Technical Requirements

**Extension Side (TypeScript/JavaScript)**
- VS Code Extension API
- Language Client (for LSP)
- Tree View providers (for template explorer)
- Webview API (for configuration UI)

**Runtime Side (.NET)**
- Target: net8.0 (cross-platform)
- Dependencies:
  - CodegenCS.Core
  - CodegenCS.Runtime (refactored for cross-platform)
  - CodegenCS.Tools.TemplateLauncher
- Communication: Language Server Protocol or JSON-RPC

#### Architecture Diagram
```
┌─────────────────────────────────────────┐
│   VS Code Extension (TypeScript)        │
│   - Commands                            │
│   - UI/UX                               │
│   - File watchers                       │
└──────────────┬──────────────────────────┘
               │ LSP/JSON-RPC
┌──────────────▼──────────────────────────┐
│   CodegenCS.Runtime.VSCode (.NET)       │
│   - Template execution                  │
│   - Workspace management                │
│   - Code generation                     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│   CodegenCS.Core + Tools                │
│   - Template compilation                │
│   - Model processing                    │
│   - Code generation engine              │
└─────────────────────────────────────────┘
```

#### Development Workflow
1. **Set up extension workspace**
   ```bash
   mkdir -p src/VSCode/CodegenCS.VSCode.Extension
   cd src/VSCode/CodegenCS.VSCode.Extension
   npm init -y
   npm install -D @types/vscode @types/node typescript
   yo code  # Use Yeoman to scaffold extension
   ```

2. **Set up .NET runtime project**
   ```bash
   dotnet new classlib -n CodegenCS.Runtime.VSCode -o src/VSCode/CodegenCS.Runtime.VSCode
   ```

3. **Reference existing projects**
   - Use CodegenCS.Runtime as base
   - Extract platform-agnostic interfaces
   - Implement VS Code-specific providers

4. **Test in Extension Development Host**
   - Press F5 in VS Code
   - Test in Extension Development Host window
   - Iterate on features

#### Migration Strategy
- **Coexistence**: VS and VS Code extensions can coexist
- **Shared Core**: Reuse all core CodegenCS libraries
- **Platform Detection**: Runtime detects environment and adapts
- **Feature Parity**: Start with core features, add advanced features incrementally

#### Success Metrics
- [ ] Extension loads in VS Code on Windows, Linux, macOS
- [ ] Can execute .csx templates from workspace
- [ ] Output appears in CodegenCS output channel
- [ ] Generated files written to workspace
- [ ] IntelliSense works in .csx files
- [ ] Template discovery and management functional

## References

- [.NET Cross-Platform Testing](https://learn.microsoft.com/en-us/dotnet/core/testing/)
- [PowerShell Cross-Platform Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/writing-portable-modules)
