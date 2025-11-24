# File System Abstraction Implementation Plan

## Overview

**Goal**: Replace System.IO with [Testably.Abstractions](https://github.com/Testably-org/Testably.Abstractions) throughout CodegenCS for cross-platform testing and consistent filesystem behavior.

**Strategy**: Static wrapper pattern in `CodegenCS.IO` namespace with nested DI classes for composition root injection.

**Current Progress** (~30% complete):
- ✅ Testably.Abstractions 10.0.0 added to CodegenCS.Core.csproj
- ✅ CodegenCS.IO namespace created with FileSystem.cs skeleton
- ✅ Using System.IO.Abstractions interfaces (IFileSystem, IFile, IDirectory, IPath)
- ✅ 5 files already using `using CodegenCS.IO;`
- ⏸️ Path.cs exists but throws NotImplementedException
- ⏸️ File and Directory static wrappers not created yet

**Estimated Completion**: 1-2 days

## Current State Analysis

### Usage Statistics (Actual Codebase)

Total System.IO API calls analyzed: ~470 occurrences

**Most Common Operations (Top 10)**:

| Method | Count | Use Case |
|--------|-------|----------|
| `Path.Combine` | 106 | Path manipulation (platform-agnostic joining) |
| `File.Exists` | 45 | Check file existence before operations |
| `Directory.GetCurrentDirectory` | 39 | Get working directory for relative paths |
| `File.ReadAllText` | 28 | Read template/config files |
| `File.Delete` | 26 | Cleanup generated files in tests |
| `Path.GetTempPath` | 23 | Create temp directories for isolated tests |
| `Path.GetFileNameWithoutExtension` | 22 | Extract base filename |
| `File.WriteAllText` | 22 | Write generated code |
| `Path.GetDirectoryName` | 20 | Extract parent directory |
| `Directory.Exists` | 14 | Check directory before creation |

**Complete API Surface Used**:
- **File Operations** (113 calls): Exists, ReadAllText, WriteAllText, Delete, ReadAllBytes, Create, Open, Copy, Move
- **Directory Operations** (79 calls): GetCurrentDirectory, Exists, CreateDirectory, GetFiles, Delete, EnumerateFiles, EnumerateDirectories
- **Path Operations** (278 calls): Combine, GetTempPath, GetFileNameWithoutExtension, GetDirectoryName, GetFullPath, GetExtension, GetFileName, DirectorySeparatorChar, IsPathRooted, GetInvalidPathChars, GetInvalidFileNameChars

### Why Testably.Abstractions?

**Cross-Platform Behaviors to Handle**:
1. **Path Separators**: Windows `\` vs Linux `/`, mixed separator handling
2. **Case Sensitivity**: Windows case-insensitive vs Linux case-sensitive
3. **Path Roots**: Windows drive letters `C:\` vs Linux single root `/`
4. **Invalid Characters**: Different rules per platform
5. **Line Endings**: CRLF vs LF
6. **File Permissions**: ACLs vs Unix permissions
7. **Path Length Limits**: Windows 260 chars limitation
8. **Symlink Behavior**: Platform differences

**What Testably.Abstractions Provides**:
- ✅ Simulates Windows on Linux and vice versa
- ✅ Configurable platform behavior
- ✅ Handles all path separator edge cases
- ✅ Correct case sensitivity per platform
- ✅ Invalid character validation per platform
- ✅ Drive letter support on non-Windows
- ✅ Path length limitation simulation
- ✅ Symlink simulation
- ✅ File system watcher simulation
- ✅ 15,000+ LOC (lines of code) handling edge cases
- ✅ 3+ years of battle-testing

**Drawbacks are Acceptable**:
- External dependency (~100KB): CodegenCS already has dependencies
- Large API surface: Use what you need, extras available if needed
- Learning curve: API is identical to System.IO

## Architecture

### Static Wrapper Pattern with Nested DI Classes

The `CodegenCS.IO` namespace provides static access to filesystem operations while preserving pure dependency injection at composition roots.

**Most Common Usage - Path operations** (~278 calls in codebase):

```csharp
namespace CodegenCS.IO
{
    public static class Path
    {
        internal static IPath CurrentPath { get; private set; }

        // Public static interface - what 99% of developers use
        public static string Combine(params string[] paths)
            => CurrentPath.Combine(paths);

        public static string GetFileName(string path)
            => CurrentPath.GetFileName(path);

        public static string GetDirectoryName(string path)
            => CurrentPath.GetDirectoryName(path);

        public static string GetExtension(string path)
            => CurrentPath.GetExtension(path);

        // ... all other Path methods delegate to CurrentPath
        public class TestablePath:IPath // you register this as the path Service
        {
	        private IPath path;
	        public TestablePath(IPath path)
		    {
			    CurrentPath = path;
			    this.path = path;
	        }
	        public string GetExtension(string path) => path.GetExtension(path);
	    }

        // Nested class for DI injection at composition root ONLY
        internal class TestableFileSystem : IFileSystem
        {
            readonly IFileSystem fileSystem;

            public TestableFileSystem(IFileSystem fileSystem)
            {
                this.fileSystem = fileSystem;
                CurrentFileSystem = fileSystem;  // Sets static context
            }

            // IFileSystem interface implementation
            public IPath Path => fileSystem.Path;
            public IFile File => fileSystem.File;
            public IDirectory Directory => fileSystem.Directory;
            // ... other members
        }
    }
}
```

**FileSystem class:**

```csharp
namespace CodegenCS.IO
{
    public static class FileSystem
    {
        internal static IFileSystem CurrentFileSystem { get; private set; }

        // Provides access to all filesystem operations
        public static IFile File => CurrentFileSystem.File;
        public static IDirectory Directory => CurrentFileSystem.Directory;
        public static IPath Path => CurrentFileSystem.Path;

        // Nested class for DI injection - called once at startup
        public class TestableFileSystem : IFileSystem
        {
            readonly IFileSystem fileSystem;

            public TestableFileSystem(IFileSystem fileSystem)
            {
                this.fileSystem = fileSystem;
                CurrentFileSystem = fileSystem;
            }

            public IFile File => fileSystem.File;
            public IDirectory Directory => fileSystem.Directory;
            public IPath Path => fileSystem.Path;
            // ... other members
        }
    }
}
```

**Key Design Principles**:

1. **Developer-facing API**: Static members like `Path.Combine()`, `File.ReadAllText()`, `Directory.GetFiles()`
2. **DI at composition root**: Nested `TestableFileSystem` class takes `IFileSystem` via constructor
3. **Single registration**: One `IFileSystem` instance serves all Path/File/Directory operations
4. **No constructor pollution**: Application code never needs `IFileSystem` parameters
5. **Pure DI preserved**: Composition root explicitly injects real or mock filesystem

## Usage Examples

### Application Code (What Developers See)

```csharp
using CodegenCS.IO;

public class MyTemplate
{
    public void Main(ICodegenTextWriter writer)
    {
        // Clean static API - no IFileSystem fields or parameters needed

        // Most common: Path operations (278 calls in codebase)
        var outputPath = Path.Combine(
            Directory.GetCurrentDirectory(),
            "Generated",
            "output.cs"
        );
        var fileName = Path.GetFileNameWithoutExtension(outputPath);

        // File operations (113 calls)
        if (!File.Exists(outputPath))
        {
            File.WriteAllText(outputPath, writer.GetContents());
        }

        // Directory operations (79 calls)
        var files = Directory.GetFiles("/some/path", "*.cs");
        var content = File.ReadAllText(files[0]);
        foreach file in files
        {
	        IFileInfo fileInfo = FileInfo.New(file);
	        ShowFileInfo(fileInfo)
        }
    }
}
```

### Composition Root (Entry Points)

Four entry points need filesystem initialization. Each uses the existing `DependencyContainer` pattern to register `IFileSystem`.

#### CLI Tool Entry Point

**File**: `src/Tools/dotnet-codegencs/Commands/TemplateRunCommand.cs` (line 83)

```csharp
using CodegenCS.IO;
using Testably.Abstractions;
using DependencyContainer = CodegenCS.Utils.DependencyContainer;

public class TemplateRunCommand
{
    DependencyContainer _dependencyContainer;

    public TemplateRunCommand()
    {
        // Existing DI container initialization
        _dependencyContainer = new DependencyContainer().AddConsole();

        // Register IFileSystem and its components as singletons
        var fileSystem = new Testably.Abstractions.FileSystem();
        _dependencyContainer.RegisterSingleton<IFileSystem>(fileSystem);
        _dependencyContainer.RegisterSingleton<IFile>(fileSystem.File);
        _dependencyContainer.RegisterSingleton<IDirectory>(fileSystem.Directory);
        _dependencyContainer.RegisterSingleton<IPath>(fileSystem.Path);
        _dependencyContainer.RegisterSingleton<IFileInfoFactory>(fileSystem.FileInfo);
        _dependencyContainer.RegisterSingleton<IDirectoryInfoFactory>(fileSystem.DirectoryInfo);
        _dependencyContainer.RegisterSingleton<IDriveInfoFactory>(fileSystem.DriveInfo);
    }

    private async Task<int> HandleCommand(InvocationContext context, ParseResult parseResult, CommandArgs args)
    {
        // Inject filesystem via DI container - sets ambient context
        var fileSystem = _dependencyContainer.Resolve<IFileSystem>();
        var _ = new FileSystem.TestableFileSystem(fileSystem);

        // Register ExecutionContext (existing pattern)
        _dependencyContainer.RegisterSingleton<ExecutionContext>(() => executionContext);
        _dependencyContainer.AddModelFactory(searchPaths);

        // Create launcher with DI container (existing pattern)
        _launcher = new TemplateLauncher.TemplateLauncher(_logger, _ctx, _dependencyContainer, _verboseMode);

        // ... rest of command execution
    }
}
```

#### MSBuild Task Entry Point

**File**: `src/MSBuild/CodegenCS.MSBuild/CodegenBuildTask.cs` (line 229)

```csharp
using CodegenCS.IO;
using Testably.Abstractions;

public class CodegenBuildTask : Task
{
    public override bool Execute()
    {
        // ... validate inputs
        _codegenContext = new DotNetCodegenContext();
        _outputFolder = new FileInfo(templatePath).Directory.FullName;

        var searchPaths = new string[] { new FileInfo(templateItemPath).Directory.FullName, _executionFolder };

        // Existing DI container initialization
        var dependencyContainer = new DependencyContainer().AddModelFactory(searchPaths);

        // Register IFileSystem and its components as singletons
        var fileSystem = new Testably.Abstractions.FileSystem();
        dependencyContainer.RegisterSingleton<IFileSystem>(fileSystem);
        dependencyContainer.RegisterSingleton<IFile>(fileSystem.File);
        dependencyContainer.RegisterSingleton<IDirectory>(fileSystem.Directory);
        dependencyContainer.RegisterSingleton<IPath>(fileSystem.Path);
        dependencyContainer.RegisterSingleton<IFileInfoFactory>(fileSystem.FileInfo);
        dependencyContainer.RegisterSingleton<IDirectoryInfoFactory>(fileSystem.DirectoryInfo);
        dependencyContainer.RegisterSingleton<IDriveInfoFactory>(fileSystem.DriveInfo);

        // Inject filesystem via DI container - sets ambient context
        var _ = new FileSystem.TestableFileSystem(fileSystem);

        // Register ExecutionContext (existing pattern)
        dependencyContainer.RegisterSingleton<ExecutionContext>(() => _codegenExecutionContext);

        // Create launcher with DI container (existing pattern)
        var launcher = new TemplateLauncher.TemplateLauncher(_logger, _codegenContext, dependencyContainer, verboseMode: false);

        // ... execute templates
    }
}
```

#### VS Extension Entry Point

**File**: `src/VisualStudio/Shared/RunTemplate/RunTemplateCommand.cs` (line 98)

```csharp
using CodegenCS.IO;
using Testably.Abstractions;

sealed class RunTemplateCommand
{
    private void Execute(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();

        try
        {
            var solution = (IVsSolution)Package.GetGlobalService(typeof(IVsSolution));
            var selectedItems = VSUtils.GetSelectedItems(_dte).ToList();

            if (selectedItems.Count() == 0)
            {
                VSUtils.ShowError(package, "Should select at least one template");
                return;
            }

            // Create DI container for this execution
            var dependencyContainer = new DependencyContainer();

            // Register IFileSystem and its components as singletons
            var fileSystem = new Testably.Abstractions.FileSystem();
            dependencyContainer.RegisterSingleton<IFileSystem>(fileSystem);
            dependencyContainer.RegisterSingleton<IFile>(fileSystem.File);
            dependencyContainer.RegisterSingleton<IDirectory>(fileSystem.Directory);
            dependencyContainer.RegisterSingleton<IPath>(fileSystem.Path);
            dependencyContainer.RegisterSingleton<IFileInfoFactory>(fileSystem.FileInfo);
            dependencyContainer.RegisterSingleton<IDirectoryInfoFactory>(fileSystem.DirectoryInfo);
            dependencyContainer.RegisterSingleton<IDriveInfoFactory>(fileSystem.DriveInfo);

            // Inject filesystem via DI container - sets ambient context
            var _ = new FileSystem.TestableFileSystem(fileSystem);

            // ... validate and run templates with dependencyContainer
        }
        catch { }
    }
}
```

#### Source Generator Entry Point

**File**: `src/SourceGenerator/CodegenCS.SourceGenerator/CodegenGenerator.cs` (line 64)

```csharp
using CodegenCS.IO;
using Testably.Abstractions;

[Generator]
public class CodegenGenerator : ISourceGenerator
{
    public void Initialize(GeneratorInitializationContext initializationContext)
    {
        // Empty - required by interface
    }

    public void Execute(GeneratorExecutionContext executionContext)
    {
        try
        {
            _executionContext = executionContext;

            // Create DI container for this generation
            var dependencyContainer = new DependencyContainer();

            // Register IFileSystem and its components as singletons
            var fileSystem = new Testably.Abstractions.FileSystem();
            dependencyContainer.RegisterSingleton<IFileSystem>(fileSystem);
            dependencyContainer.RegisterSingleton<IFile>(fileSystem.File);
            dependencyContainer.RegisterSingleton<IDirectory>(fileSystem.Directory);
            dependencyContainer.RegisterSingleton<IPath>(fileSystem.Path);
            dependencyContainer.RegisterSingleton<IFileInfoFactory>(fileSystem.FileInfo);
            dependencyContainer.RegisterSingleton<IDirectoryInfoFactory>(fileSystem.DirectoryInfo);
            dependencyContainer.RegisterSingleton<IDriveInfoFactory>(fileSystem.DriveInfo);

            // Inject filesystem via DI container - sets ambient context
            var _ = new FileSystem.TestableFileSystem(fileSystem);

            string[] validExtensions = new string[] { ".csx", ".cs", ".cgcs" };
            foreach (AdditionalText template in executionContext.AdditionalFiles)
            {
                executionContext.AnalyzerConfigOptions.GetOptions(template)
                    .TryGetValue("build_metadata.AdditionalFiles.CodegenCSOutput", out var outputType);

                if (string.IsNullOrEmpty(Path.GetExtension(template.Path)) ||
                    !validExtensions.Contains(Path.GetExtension(template.Path).ToLower()))
                    continue;

                // ... process templates
            }
        }
        catch { }
    }
}
```

### Test Setup

```csharp
using CodegenCS.IO;
using Testably.Abstractions.Testing;

public abstract class BaseTest
{
    protected DependencyContainer _dependencyContainer;

    [SetUp]
    public void BaseSetUp()
    {
        // Create MockFileSystem for test
        var mockFs = new MockFileSystem();

        // Register in DI container as singletons
        _dependencyContainer = new DependencyContainer();
        _dependencyContainer.RegisterSingleton<IFileSystem>(mockFs);
        _dependencyContainer.RegisterSingleton<IFile>(mockFs.File);
        _dependencyContainer.RegisterSingleton<IDirectory>(mockFs.Directory);
        _dependencyContainer.RegisterSingleton<IPath>(mockFs.Path);
        _dependencyContainer.RegisterSingleton<IFileInfoFactory>(mockFs.FileInfo);
        _dependencyContainer.RegisterSingleton<IDirectoryInfoFactory>(mockFs.DirectoryInfo);
        _dependencyContainer.RegisterSingleton<IDriveInfoFactory>(mockFs.DriveInfo);

        // Set ambient context for static FileSystem.* calls
        var _ = new FileSystem.TestableFileSystem(mockFs);
    }
}

[Test]
public void TestTemplate()
{
    // Setup test data using ambient context
    FileSystem.File.WriteAllText("template.csx", "template content");

    // Act - all FileSystem.* calls automatically use mockFs
    var generator = new CodeGenerator();
    generator.Generate("template.csx");

    // Assert
    Assert.That(FileSystem.File.Exists("output.cs"), Is.True);

    // Can also resolve from DI container if needed
    var path = _dependencyContainer.Resolve<IPath>();
    Assert.That(path.Combine("a", "b"), Is.EqualTo("a/b")); // MockFileSystem default
}
```

### Cross-Platform Testing

```csharp
[Test]
public void TestWindowsBehaviorOnLinux()
{
    // Simulate Windows filesystem on any platform
    var windowsFs = new MockFileSystem(
        new MockFileSystemOptions { OSPlatform = OSPlatform.Windows }
    );
    var _ = new FileSystem.TestableFileSystem(windowsFs);

    windowsFs.File.WriteAllText(@"C:\template.csx", "content");

    // Case-insensitive on Windows
    Assert.That(FileSystem.File.Exists(@"C:\TEMPLATE.CSX"), Is.True);
}

[Test]
public void TestLinuxBehaviorOnWindows()
{
    // Simulate Linux filesystem on any platform
    var linuxFs = new MockFileSystem(
        new MockFileSystemOptions { OSPlatform = OSPlatform.Linux }
    );
    var _ = new FileSystem.TestableFileSystem(linuxFs);

    linuxFs.File.WriteAllText("/home/template.csx", "content");

    // Case-sensitive on Linux
    Assert.That(FileSystem.File.Exists("/home/TEMPLATE.CSX"), Is.False);
}
```

## Implementation Phases

### Phase 1: Complete Static Wrapper Infrastructure

**Duration**: 2-4 hours ⏰
**Status**: ⏸️ **50% Complete** - skeleton exists, needs implementation
**Priority**: Critical - Foundation for all other work

**Already Done**:
- ✅ CodegenCS.IO namespace exists
- ✅ FileSystem.cs created with static properties
- ✅ Path.cs created (needs implementation)
- ✅ Testably.Abstractions 10.0.0 added to project
- ✅ 5 files already reference CodegenCS.IO

#### 1.1 Complete FileSystem.cs Implementation (30-60 min)

**Status**: Skeleton exists, needs completion

**Tasks**:
- [ ] Keep `CurrentFileSystem` static property (already correct pattern)
- [ ] Add default initialization if null
- [ ] Complete TestableFileSystem nested class implementation
- [ ] Remove Path.cs nested class (redundant - use FileSystem.Path directly)

**File to Modify**:
- ✏️ `src/Core/CodegenCS/IO/FileSystem.cs`

#### 1.2 Update Test Infrastructure (15-30 min)

**Tasks**:
- [ ] Update BaseTest.cs to use `new FileSystem.TestableFileSystem(mockFs)`
- [ ] Remove temp directory cleanup (MockFileSystem is in-memory)

**File to Modify**:
- ✏️ `src/Core/CodegenCS.Tests/BaseTest.cs`

**Example**:
```csharp
using CodegenCS.IO;
using Testably.Abstractions.Testing;

public abstract class BaseTest
{
    [SetUp]
    public void BaseSetUp()
    {
        // Inject MockFileSystem via nested class
        var mockFs = new MockFileSystem();
        var _ = new FileSystem.TestableFileSystem(mockFs);
    }

    // No [TearDown] cleanup needed for in-memory filesystem!
}
```

### Phase 2: Core Library Migration

**Duration**: 2-3 hours ⏰
**Priority**: High - Most foundational code
**Status**: 🔜 Ready to start after Phase 1

#### 2.1 CodegenCS Core Project
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`
- [ ] No code changes needed - API is identical!

**Files to Scan**:
```bash
src/Core/CodegenCS/**/*.cs
```

**Migration Pattern**:
```csharp
// Before:
using System.IO;

string content = File.ReadAllText(path);

// After:
using CodegenCS.IO;

string content = FileSystem.File.ReadAllText(path);
```

#### 2.2 CodegenCS.Runtime Project
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`
- [ ] No constructor changes needed

**Files to Scan**:
```bash
src/Core/CodegenCS.Runtime/**/*.cs
```

#### 2.3 CodegenCS.DotNet Project
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`

**Files to Scan**:
```bash
src/Core/CodegenCS.DotNet/**/*.cs
```

### Phase 3: Tools Migration

**Duration**: 2-3 hours ⏰
**Priority**: High - Heavy file I/O usage
**Status**: 🔜 TemplateLauncher already has `using CodegenCS.IO`

#### 3.1 TemplateLauncher
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`
- [ ] No constructor changes needed!

**Files to Modify**:
- `src/Tools/TemplateLauncher/TemplateLauncher.cs`

**Migration** (trivial):
```csharp
// Just change the using statement
using CodegenCS.IO;  // Instead of System.IO

public class TemplateLauncher
{
    // Constructor stays exactly the same - no IFileSystem parameter needed!
    public TemplateLauncher(
        ILogger logger,
        ICodegenContext ctx,
        DependencyContainer dependencyContainer,
        bool verboseMode = false)
    {
        _logger = logger;
        _ctx = ctx;
        _dependencyContainer = dependencyContainer;
        VerboseMode = verboseMode;
    }

    // All File/Directory/Path calls work unchanged
    public void LoadTemplate(string path)
    {
        if (!File.Exists(path))  // Uses ambient context
            throw new FileNotFoundException(path);
    }
}
```

#### 3.2 TemplateBuilder
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`

**Files to Modify**:
- `src/Tools/TemplateBuilder/TemplateBuilder.cs`

#### 3.3 CLI Tool (dotnet-codegencs)
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;` in all files
- [ ] Set `FileSystemContext.Current = new FileSystem()` in Program.cs (optional, it's the default)

**Files to Modify**:
- `src/Tools/dotnet-codegencs/Program.cs`
- CLI command handlers

### Phase 4: Test Migration

**Duration**: 2-3 hours ⏰
**Priority**: High - Validates all changes
**Status**: 🔜 BaseTest files already have `using CodegenCS.IO`

#### 4.1 Unit Tests (Use MockFileSystem)
- [ ] Update CodegenCS.Tests to set FileSystemContext.Current in [SetUp]
- [ ] Add cross-platform test cases (Windows behavior on Linux, vice versa)
- [ ] Remove temp directory cleanup code (MockFileSystem is in-memory)
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`

**Files to Scan**:
```bash
src/Core/CodegenCS.Tests/**/*Tests.cs
```

**Test Pattern** (Ambient Context):
```csharp
using CodegenCS.IO;  // Static wrappers

[Test]
public void GeneratesCorrectOutput()
{
    // Arrange - ambient context set by BaseTest.BaseSetUp()
    File.WriteAllText("template.csx", templateContent);
    File.WriteAllText("model.json", modelContent);

    // Act - no IFileSystem parameters anywhere!
    var context = new CodegenContext();
    var generator = new CodeGenerator();
    generator.Generate("template.csx", "model.json");

    // Assert
    Assert.That(File.Exists("output.cs"), Is.True);
    Assert.That(File.ReadAllText("output.cs"), Does.Contain("expected"));
}
// No [TearDown] cleanup needed!
```

#### 4.2 Integration Tests (Keep Real FileSystem)
- [ ] Document that SourceGenerator.Tests uses real file system
- [ ] Document that CLI tool tests use real file system
- [ ] Add proper [TearDown] cleanup for integration tests
- [ ] Use temp directories with Guid names for isolation

**Important**: Integration tests that invoke:
- MSBuild (`dotnet build`)
- External processes (`dotnet-codegencs`)
- Roslyn compilation

Should NOT use MockFileSystem - they need real file I/O.

**Integration Test Pattern**:
```csharp
using CodegenCS.IO;  // Can still use it with real filesystem

[Category("Integration")]
[Test]
public void RealBuildProcess()
{
    // Ensure we're using real filesystem for integration tests
    FileSystemContext.Current = new FileSystem();

    var testDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
    Directory.CreateDirectory(testDir);

    try
    {
        // Test with real file system
        File.WriteAllText(Path.Combine(testDir, "test.csproj"), projectContent);
        var (exitCode, output) = RunDotNetBuild(testDir);
        Assert.That(exitCode, Is.EqualTo(0));
    }
    finally
    {
        if (Directory.Exists(testDir))
            Directory.Delete(testDir, recursive: true);
    }
}
```

### Phase 5: Models Projects

**Duration**: 1-2 hours ⏰
**Priority**: Medium - Less file I/O
**Status**: 🔜 Just change using statements

#### 5.1 DbSchema Projects
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`

**Files to Modify**:
- `src/Models/CodegenCS.Models.DbSchema/**/*.cs`
- `src/Models/CodegenCS.Models.DbSchema.Extractor/**/*.cs`

#### 5.2 NSwag Adapter
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`

**Files to Modify**:
- `src/Models/CodegenCS.Models.NSwagAdapter/**/*.cs`

#### 5.3 ModelFactory
- [ ] No interface changes needed!
- [ ] Just change using statement

**Files to Modify**:
- `src/Tools/TemplateLauncher/ModelFactoryBuilder.cs`

### Phase 6: MSBuild Integration

**Duration**: 30 minutes ⏰
**Priority**: Medium
**Status**: 🔜 Single file change

#### 6.1 MSBuild Task
- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`
- [ ] Optionally set `FileSystemContext.Current = new FileSystem()` (it's the default anyway)

**Files to Modify**:
- `src/MSBuild/CodegenCS.MSBuild/CodegenBuildTask.cs`

**Note**: MSBuild tasks automatically use real FileSystem (the default).

### Phase 7: Source Generator

**Duration**: 30 minutes ⏰
**Priority**: Low - Runs during compilation
**Status**: 🔜 Quick evaluation

#### 7.1 Source Generator Project
- [ ] Evaluate if IFileSystem makes sense for Roslyn source generators
- [ ] Document decision (likely keep System.IO for compilation context)

**Files to Evaluate**:
- `src/SourceGenerator/CodegenCS.SourceGenerator/CodegenGenerator.cs`

**Note**: Source generators run in compiler context - may need real file system.

### Phase 8: Documentation & Cleanup

**Duration**: 1 hour ⏰
**Priority**: High - Complete the migration
**Status**: 🔜 Final polish

#### 8.1 Update Documentation
- [ ] Update README.md with IFileSystem injection examples
- [ ] Document cross-platform testing capability
- [ ] Add migration guide for template authors
- [ ] Update CONTRIBUTING.md

#### 8.2 Add Examples
- [ ] Create example template using IFileSystem
- [ ] Add cross-platform test examples
- [ ] Document best practices

#### 8.3 Final Validation
- [ ] Run all unit tests
- [ ] Run all integration tests
- [ ] Test on both Windows and Linux
- [ ] Validate cross-platform behavior simulation

## Migration Checklist Template

For each project/class being migrated:

```markdown
### [Project/Class Name]

- [ ] Add reference to `CodegenCS.IO` project
- [ ] Change `using System.IO;` → `using CodegenCS.IO;`
- [ ] **No constructor changes needed!**
- [ ] **No field additions needed!**
- [ ] Verify all File/Directory/Path calls compile and work
- [ ] Update tests: set `FileSystemContext.Current = new MockFileSystem()` in [SetUp]
- [ ] Add cross-platform test cases
- [ ] Remove temp directory cleanup in tests (MockFileSystem is in-memory)
- [ ] Update documentation/examples
```

## Benefits Summary

### For Production Code
- ✅ Consistent cross-platform file system behavior
- ✅ Proven edge case handling (path lengths, invalid chars, symlinks)
- ✅ Future-proof with maintained library
- ✅ **Zero migration friction** - just change using statements
- ✅ **Preserves natural code readability** - looks exactly like System.IO
- ✅ Easy to test error conditions (permissions, disk full)

### For Testing
- ✅ **Critical**: Test Windows behavior on Linux and vice versa
- ✅ Fast in-memory tests (10-100x faster than disk I/O)
- ✅ No cleanup needed (automatic memory release)
- ✅ Isolated tests (no shared state between tests)
- ✅ Simulate file system errors easily

### For Maintenance
- ✅ No custom implementation to maintain
- ✅ Community support and regular bug fixes
- ✅ Updates for new .NET versions
- ✅ Comprehensive documentation

## Timeline Estimate

### Current Progress Assessment

**Already Done** (~30% complete):
- ✅ Testably.Abstractions package added
- ✅ CodegenCS.IO namespace created
- ✅ FileSystem.cs static wrapper skeleton exists
- ✅ 5 files already using `using CodegenCS.IO;`
- ✅ BaseTest files ready for ambient context

**Remaining Work**:

| Phase | Duration | Priority | Status |
|-------|----------|----------|--------|
| Phase 1: Complete Static Wrappers | **2-4 hours** | Critical | ⏸️ 50% Done |
| Phase 2: Core Library Migration | **2-3 hours** | High | 🔜 Next |
| Phase 3: Tools Migration | **2-3 hours** | High | 🔜 |
| Phase 4: Test Migration | **2-3 hours** | High | 🔜 |
| Phase 5: Models Projects | **1-2 hours** | Medium | 🔜 |
| Phase 6: MSBuild Integration | **30 min** | Medium | 🔜 |
| Phase 7: Source Generator | **30 min** | Low | 🔜 |
| Phase 8: Documentation | **1 hour** | High | 🔜 |
| **Total Remaining** | **1-2 days** | | |

**Revised Estimate**: ✅ **Can be completed in 1-2 days** (not 3-4 weeks!)

**Why So Much Faster**:
- ✅ No constructor changes needed - just change `using` statements
- ✅ Static wrapper infrastructure already started
- ✅ Testably.Abstractions already added
- ✅ ~30% of work already done
- ✅ Migration is literally changing `using System.IO` → `using CodegenCS.IO`

**Risk Level**: Very Low - infrastructure exists, just needs completion
**Benefit**: Complete cross-platform testing capability essential for CodegenCS

## Success Criteria

Migration is complete when:
- ✅ All production code uses `CodegenCS.IO` instead of `System.IO` directly
- ✅ All unit tests set `FileSystemContext.Current = new MockFileSystem()`
- ✅ Cross-platform tests exist (Windows behavior on Linux, Linux on Windows)
- ✅ Integration tests use real file system (default behavior)
- ✅ All tests pass on both Windows and Linux
- ✅ Documentation updated with ambient context pattern
- ✅ Zero regressions in existing functionality
- ✅ Code readability preserved - no `_fileSystem` fields everywhere

## References

- [Testably.Abstractions GitHub](https://github.com/Testably-org/Testably.Abstractions)
- [Testably.Abstractions Documentation](https://testably.github.io/Testably.Abstractions/)
- [Original Analysis](./filesystem-abstraction-analysis.md) (archived)
