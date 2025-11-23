# Cross-Platform Development Roadmap

## Current Status

### ✅ Completed
- **Build Scripts**: Standardized PowerShell scripts with try-finally blocks and consolidated tool detection
- **Core Tests**: All passing on Linux
- **CLI Tool Tests**: Fixed for cross-platform executable names and line endings
- **Solution Filter**: Created `CodegenCS-Linux.slnf` to hide Windows-only projects
- **VS Code Configuration**: Configured to exclude Visual Studio extension projects on Linux

### 🔄 Known Issues Requiring Investigation

#### 1. Test Framework Differences
**Problem**: Some tests are failing due to platform-specific output differences

**Observations**:
- Tests require framework version in filenames (e.g., `net9.0`) on Linux but not on Windows
- Console output captures from Windows don't match Linux console output
- Additional output appears on Linux that's not present in Windows captures
- Snapshot formatting differences between platforms

**Action Items**:
- [ ] Compare test output on actual Windows machine vs Linux
- [ ] Update snapshots to be platform-aware or normalize output
- [ ] Investigate if framework version in filenames is truly required or can be abstracted
- [ ] Document expected platform-specific output differences

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
**Problem**: Some tests hardcode Windows path separators or .exe extensions

**Status**:
- Fixed in BaseTest.cs for CLI tool executable names
- May exist in other test files

**Action Items**:
- [ ] Grep for hardcoded `.exe` references
- [ ] Grep for hardcoded `\` path separators
- [ ] Create cross-platform path helper utilities

### 🚫 Not Supported (Windows-Only)
- **Visual Studio Extensions**: VS2019Extension, VS2022Extension, CodegenCS.Runtime.VisualStudio
- **.NET Framework projects**: Projects targeting net4xx frameworks
- **NuGet Package Explorer**: Windows-only GUI tool (optional dev dependency)

## Platform-Specific Behaviors

### Linux
- Uses symlink-aware path resolution in build scripts
- Requires 7z (p7zip-full) for archive operations
- Uses ilspycmd for decompilation (cross-platform alternative to dnSpy)
- Line endings: LF (`\n`)
- Executable names: No `.exe` extension

### Windows
- Direct path resolution
- Uses 7-Zip from Program Files
- Uses dnSpy for decompilation
- Line endings: CRLF (`\r\n`)
- Executable names: `.exe` extension required

## Testing Strategy

### Core Tests (CodegenCS.Tests)
- **Status**: ✅ All passing on Linux
- **Approach**: Platform-agnostic code generation tests

### CLI Tool Tests (CodegenCS.Tools.CliTool.Tests)
- **Status**: ✅ Fixed for cross-platform
- **Approach**:
  - Platform-specific executable name detection
  - Environment.NewLine for line ending assertions
  - Normalized output comparison

### Source Generator Tests (CodegenCS.SourceGenerator.Tests)
- **Status**: ⚠️ Needs investigation
- **Issues**:
  - Framework version in output paths
  - Console output format differences
  - Snapshot mismatches

### Integration Tests
- **Status**: 🔍 Not yet evaluated
- **Action**: Run full test suite on both platforms and document differences

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
1. Run tests on Linux: `dotnet test src/CodegenCS.sln`
2. Verify Windows compatibility (when available):
   - Test on actual Windows machine
   - Compare snapshot outputs
   - Document any intentional platform differences

### Committing Changes
- Include cross-platform fixes in commit messages
- Update this roadmap with progress
- Document new platform-specific behaviors discovered

## Future Enhancements

### Version Management
**Current State**: Manual versioning with hardcoded `<Version>` tags in each .csproj file
- Multiple inconsistent versions (3.5.0, 3.5.2, 3.1.3, 2.0.3)
- Must manually update each file during release
- No automated version bumping

**Recommended Solution**: [Nerdbank.GitVersioning (nbgv)](https://github.com/dotnet/Nerdbank.GitVersioning)

**Action Items**:
- [ ] Install nbgv: `dotnet tool install -g nbgv`
- [ ] Initialize in repository: `nbgv install`
- [ ] Configure `version.json`:
  ```json
  {
    "$schema": "https://raw.githubusercontent.com/dotnet/Nerdbank.GitVersioning/master/src/NerdBank.GitVersioning/version.schema.json",
    "version": "3.6-preview",
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
- [ ] Remove hardcoded `<Version>` tags from .csproj files
- [ ] Add `<PackageReference Include="Nerdbank.GitVersioning" />` to Directory.Build.props
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

**Solution**: [Testably.Abstractions](https://github.com/Testably/Testably.Abstractions)
- Provides `IFileSystem` abstraction over System.IO
- Drop-in replacement with minimal code changes
- Full mocking support for unit tests
- Cross-platform path handling built-in
- Same API as System.IO (easy migration)

**Implementation Plan**:
1. **Add Package References**
   ```bash
   # Add to test projects
   dotnet add src/Core/CodegenCS.Tests/CodegenCS.Tests.csproj package Testably.Abstractions.Testing
   dotnet add src/Tools/CodegenCS.Tools.CliTool.Tests/CodegenCS.Tools.CliTool.Tests.csproj package Testably.Abstractions.Testing
   dotnet add src/SourceGenerator/CodegenCS.SourceGenerator.Tests/CodegenCS.SourceGenerator.Tests.csproj package Testably.Abstractions.Testing

   # Add to runtime/core projects for production use
   dotnet add src/Core/CodegenCS.Runtime/CodegenCS.Runtime.csproj package Testably.Abstractions
   ```

2. **Refactor Code to Use IFileSystem**
   ```csharp
   // Before:
   File.WriteAllText(path, content);
   var exists = Directory.Exists(path);

   // After:
   _fileSystem.File.WriteAllText(path, content);
   var exists = _fileSystem.Directory.Exists(path);
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

4. **Fix Current Test Issues**
   - [ ] Replace `File.*` calls with `_fileSystem.File.*`
   - [ ] Replace `Directory.*` calls with `_fileSystem.Directory.*`
   - [ ] Replace `Path.Combine` with `_fileSystem.Path.Combine` (handles separators)
   - [ ] Update hardcoded paths to use `_fileSystem.Path.GetTempPath()`
   - [ ] Use in-memory file system for unit tests (faster, isolated)

5. **Benefits**
   - ✅ Tests run in-memory (10-100x faster)
   - ✅ No file system cleanup needed
   - ✅ Tests are isolated (no shared state)
   - ✅ Cross-platform path handling automatic
   - ✅ Easy to simulate file system errors
   - ✅ No actual disk I/O in unit tests

**Priority Action Items**:
- [ ] Add Testably.Abstractions to test projects
- [ ] Refactor BaseTest.cs to use IFileSystem
- [ ] Update failing tests with path issues first
- [ ] Migrate file I/O operations in core libraries
- [ ] Add file system mocking examples to docs
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
