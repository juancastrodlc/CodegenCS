# File System Abstraction Analysis

## Usage Statistics (Actual Codebase)

Total System.IO API calls analyzed: ~470 occurrences

### Most Common Operations (Top 10)

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

### Complete API Surface Used

**File Operations (113 calls)**
- `File.Exists` (45) - Check file existence
- `File.ReadAllText` (28) - Read entire file
- `File.WriteAllText` (22) - Write entire file  
- `File.Delete` (26) - Remove files
- `File.ReadAllBytes` (4) - Read binary files
- `File.Create`, `File.Open`, `File.Copy`, `File.Move` (<10 combined)

**Directory Operations (79 calls)**
- `Directory.GetCurrentDirectory` (39) - Get working dir
- `Directory.Exists` (14) - Check existence
- `Directory.CreateDirectory` (11) - Create dir
- `Directory.GetFiles` (8) - List files
- `Directory.Delete` (4) - Remove dir
- `Directory.EnumerateFiles`, `Directory.EnumerateDirectories` (<5 combined)

**Path Operations (278 calls)**
- `Path.Combine` (106) - Join path segments
- `Path.GetTempPath` (23) - Get temp directory
- `Path.GetFileNameWithoutExtension` (22) - Extract base name
- `Path.GetDirectoryName` (20) - Get parent dir
- `Path.GetFullPath` (14) - Resolve to absolute
- `Path.GetExtension` (11) - Get file extension
- `Path.GetFileName` (8) - Get filename only
- `Path.DirectorySeparatorChar` (16) - Platform separator
- `Path.IsPathRooted` (2) - Check if absolute
- `Path.GetInvalidPathChars`, `Path.GetInvalidFileNameChars` (6) - Validation

## Decision: Custom Lightweight Abstraction

### Rationale
Given the **limited API surface** (only ~15 distinct methods heavily used), creating a custom abstraction is **feasible and preferable** to:

✅ **Advantages of Custom Abstraction**:
1. **Zero external dependencies** - No NuGet package required
2. **Minimal code** - ~200-300 lines total
3. **Exact needs** - Only implement what we actually use
4. **Full control** - Easy to extend/modify
5. **No version conflicts** - No dependency chain
6. **Easier to understand** - Simple interface
7. **Better for testing** - In-memory implementation straightforward

❌ **Disadvantages of Testably.Abstractions**:
1. External dependency (adds ~100KB+ to packages)
2. Large API surface we don't need (100+ methods)
3. Version management overhead
4. Potential breaking changes in updates
5. Learning curve for contributors

### Implementation Plan

#### 1. Define Minimal Interface

```csharp
// src/Core/CodegenCS/IO/IFileSystem.cs
namespace CodegenCS.IO;

public interface IFileSystem
{
    IFile File { get; }
    IDirectory Directory { get; }
    IPath Path { get; }
}

public interface IFile
{
    bool Exists(string path);
    string ReadAllText(string path);
    void WriteAllText(string path, string contents);
    byte[] ReadAllBytes(string path);
    void WriteAllBytes(string path, byte[] bytes);
    void Delete(string path);
    void Copy(string source, string dest, bool overwrite = false);
}

public interface IDirectory
{
    bool Exists(string path);
    void CreateDirectory(string path);
    void Delete(string path, bool recursive = false);
    string[] GetFiles(string path, string searchPattern = "*", SearchOption options = SearchOption.TopDirectoryOnly);
    string GetCurrentDirectory();
}

public interface IPath
{
    string Combine(params string[] paths);
    string GetTempPath();
    string GetDirectoryName(string path);
    string GetFileName(string path);
    string GetFileNameWithoutExtension(string path);
    string GetExtension(string path);
    string GetFullPath(string path);
    bool IsPathRooted(string path);
    char DirectorySeparatorChar { get; }
    char AltDirectorySeparatorChar { get; }
}
```

#### 2. Production Implementation (Real File System)

```csharp
// src/Core/CodegenCS/IO/PhysicalFileSystem.cs
namespace CodegenCS.IO;

public class PhysicalFileSystem : IFileSystem
{
    public IFile File => _file ??= new PhysicalFile();
    public IDirectory Directory => _directory ??= new PhysicalDirectory();
    public IPath Path => _path ??= new PhysicalPath();
    
    private IFile? _file;
    private IDirectory? _directory;
    private IPath? _path;
}

internal class PhysicalFile : IFile
{
    public bool Exists(string path) => System.IO.File.Exists(path);
    public string ReadAllText(string path) => System.IO.File.ReadAllText(path);
    public void WriteAllText(string path, string contents) => System.IO.File.WriteAllText(path, contents);
    // ... other methods just delegate to System.IO
}

internal class PhysicalDirectory : IDirectory
{
    public bool Exists(string path) => System.IO.Directory.Exists(path);
    public void CreateDirectory(string path) => System.IO.Directory.CreateDirectory(path);
    // ... delegates
}

internal class PhysicalPath : IPath
{
    public string Combine(params string[] paths) => System.IO.Path.Combine(paths);
    public char DirectorySeparatorChar => System.IO.Path.DirectorySeparatorChar;
    // ... delegates
}
```

#### 3. Test Implementation (In-Memory)

```csharp
// src/Core/CodegenCS.Tests/IO/InMemoryFileSystem.cs
namespace CodegenCS.Tests.IO;

public class InMemoryFileSystem : IFileSystem
{
    private readonly Dictionary<string, string> _files = new();
    private readonly HashSet<string> _directories = new();
    
    public IFile File => _file ??= new InMemoryFile(this);
    public IDirectory Directory => _directory ??= new InMemoryDirectory(this);
    public IPath Path => _path ??= new InMemoryPath();
    
    private IFile? _file;
    private IDirectory? _directory;
    private IPath? _path;
}

internal class InMemoryFile : IFile
{
    private readonly InMemoryFileSystem _fs;
    
    public bool Exists(string path) => _fs._files.ContainsKey(NormalizePath(path));
    public string ReadAllText(string path) => _fs._files[NormalizePath(path)];
    public void WriteAllText(string path, string contents) 
    {
        var normalized = NormalizePath(path);
        _fs._files[normalized] = contents;
        // Auto-create parent directory
        var dir = System.IO.Path.GetDirectoryName(normalized);
        if (!string.IsNullOrEmpty(dir))
            _fs._directories.Add(dir);
    }
    // ... etc
}
```

#### 4. Update BaseTest Classes

```csharp
// src/Core/CodegenCS.Tests/BaseTest.cs
namespace CodegenCS.Tests;

public abstract class BaseTest
{
    protected IFileSystem FileSystem { get; private set; } = null!;
    
    [SetUp]
    public void BaseSetUp()
    {
        // Use in-memory file system for tests
        FileSystem = new InMemoryFileSystem();
    }
}
```

#### 5. Migration Strategy

**Phase 1: Core Library** (1-2 days)
- [ ] Create interface definitions in `CodegenCS/IO/`
- [ ] Implement PhysicalFileSystem (real I/O)
- [ ] Implement InMemoryFileSystem (testing)
- [ ] Add unit tests for file system implementations

**Phase 2: Test Infrastructure** (1 day)
- [ ] Update BaseTest.cs to inject IFileSystem
- [ ] Provide helper property: `protected IFileSystem FS => FileSystem`

**Phase 3: Gradual Migration** (ongoing)
- [ ] Replace `File.*` with `FileSystem.File.*` (or `FS.File.*`)
- [ ] Replace `Directory.*` with `FileSystem.Directory.*`
- [ ] Replace `Path.*` with `FileSystem.Path.*`
- [ ] Start with test projects first
- [ ] Then migrate core libraries

**Phase 4: Production Code** (as needed)
- [ ] Inject IFileSystem via DI where needed
- [ ] Default to PhysicalFileSystem for production
- [ ] Use InMemoryFileSystem only in tests

### Code Size Estimate

| Component | Lines of Code |
|-----------|---------------|
| Interfaces | ~60 |
| PhysicalFileSystem | ~100 |
| InMemoryFileSystem | ~150 |
| Unit Tests | ~100 |
| **Total** | **~410 lines** |

Compare to Testably.Abstractions: ~15,000+ lines + external dependency

### Example Migration

**Before:**
```csharp
string content = File.ReadAllText(path);
if (!Directory.Exists(outputDir))
    Directory.CreateDirectory(outputDir);
File.WriteAllText(Path.Combine(outputDir, "output.cs"), content);
```

**After:**
```csharp
string content = FS.File.ReadAllText(path);
if (!FS.Directory.Exists(outputDir))
    FS.Directory.CreateDirectory(outputDir);
FS.File.WriteAllText(FS.Path.Combine(outputDir, "output.cs"), content);
```

### Testing Benefits

```csharp
[Test]
public void GeneratesFile()
{
    // Arrange - all in-memory, no disk I/O
    FS.File.WriteAllText("template.csx", "template content");
    
    // Act
    var generator = new CodeGenerator(FS);
    generator.Generate("template.csx");
    
    // Assert
    Assert.That(FS.File.Exists("output.cs"), Is.True);
    Assert.That(FS.File.ReadAllText("output.cs"), Does.Contain("expected"));
}
// No cleanup needed! Memory is freed automatically
```

## Critical Consideration: Cross-Platform Behavior Mocking

### The Hidden Complexity

The **real challenge** isn't abstracting System.IO APIs - it's **accurately mocking cross-platform behaviors**:

#### Platform-Specific Behaviors to Mock

1. **Path Separators**
   - Windows: `\` (backslash)
   - Linux/Mac: `/` (forward slash)
   - Must handle: `C:\Users\` vs `/home/user/`
   - Mixed separators: Windows accepts both, Linux doesn't

2. **Case Sensitivity**
   - Windows: Case-insensitive (`File.txt` == `file.txt`)
   - Linux: Case-sensitive (`File.txt` != `file.txt`)
   - Affects: File exists checks, path comparisons

3. **Path Roots**
   - Windows: Drive letters (`C:\`, `D:\`)
   - Linux: Single root (`/`)
   - UNC paths on Windows: `\\server\share\`

4. **Invalid Characters**
   - Windows: `< > : " | ? * \0-\31`
   - Linux: Only `/` and `\0`
   - Different validation rules

5. **Line Endings**
   - Windows: CRLF (`\r\n`)
   - Linux: LF (`\n`)
   - Affects: `File.ReadAllText` results

6. **File Permissions**
   - Windows: ACLs
   - Linux: Unix permissions (rwx)
   - Affects: `Directory.CreateDirectory`, file access

### Reality Check

**Custom Implementation Issues**:
```csharp
// InMemoryFileSystem needs to know:
public class InMemoryFileSystem : IFileSystem
{
    // What platform am I mocking?
    private readonly PlatformID _mockPlatform;
    
    // Path normalization - complex!
    private string NormalizePath(string path)
    {
        if (_mockPlatform == PlatformID.Unix)
        {
            // Case-sensitive
            // Only / separator
            // Reject backslashes
            // Single root /
        }
        else
        {
            // Case-insensitive (need string comparer)
            // Accept both / and \
            // Drive letters C:\
            // UNC paths \\server\
        }
    }
    
    // File.Exists needs platform-aware comparison
    public bool Exists(string path)
    {
        var normalized = NormalizePath(path);
        var comparer = _mockPlatform == PlatformID.Unix 
            ? StringComparer.Ordinal 
            : StringComparer.OrdinalIgnoreCase;
        return _files.Keys.Any(k => comparer.Equals(k, normalized));
    }
}
```

**This is NOT 400 lines - it's closer to 1500+ lines** when you handle:
- Path normalization (both platforms)
- Case sensitivity differences
- Invalid character validation
- Rooted path detection
- Relative path resolution
- Symlink behavior (Linux)
- Path length limits (Windows 260 chars)

### Testably.Abstractions Already Solved This

The library has **3+ years of cross-platform testing** and edge cases handled:
- ✅ Simulates Windows on Linux and vice versa
- ✅ Configurable platform behavior
- ✅ Handles all path separator edge cases
- ✅ Correct case sensitivity per platform
- ✅ Invalid character validation per platform
- ✅ Drive letter support on non-Windows
- ✅ 260+ path length issues
- ✅ Symlink simulation
- ✅ File system watcher simulation

### Final Recommendation

**Use Testably.Abstractions across the entire project** - both production and test code.

**Decision Rationale**:
Given the nature of CodegenCS as a **code generation tool that must work consistently across platforms**, the ability to test Windows behavior on Linux and vice versa is **essential**, not optional. The drawbacks (external dependency, larger package size) are outweighed by the critical need for:
- ✅ Cross-platform behavior testing (Windows paths on Linux, Linux paths on Windows)
- ✅ Proven battle-tested implementation (3+ years, 15,000+ LOC handling edge cases)
- ✅ Consistent file system behavior in generated code
- ✅ No risk of subtle platform-specific bugs in production

**Full Integration Approach**:
1. **Production Code**: Use Testably.Abstractions
   - Add `Testably.Abstractions` to production projects
   - Inject `IFileSystem` via dependency injection
   - Default to `new FileSystem()` (real file system)

2. **Test Code**: Use Testably.Abstractions.Testing
   - Add `Testably.Abstractions.Testing` to test projects
   - Use `MockFileSystem` with platform simulation
   - Test both Windows and Linux behaviors on any platform

**Implementation Plan**:

### Phase 1: Add Package References (Day 1)

```bash
# Production projects - Add Testably.Abstractions
dotnet add src/Core/CodegenCS/CodegenCS.csproj \
    package Testably.Abstractions
dotnet add src/Core/CodegenCS.Runtime/CodegenCS.Runtime.csproj \
    package Testably.Abstractions
dotnet add src/Tools/CodegenCS.Tools.TemplateLauncher/CodegenCS.Tools.TemplateLauncher.csproj \
    package Testably.Abstractions
dotnet add src/Tools/CodegenCS.Tools.TemplateBuilder/CodegenCS.Tools.TemplateBuilder.csproj \
    package Testably.Abstractions

# Test projects - Add Testably.Abstractions.Testing
dotnet add src/Core/CodegenCS.Tests/CodegenCS.Tests.csproj \
    package Testably.Abstractions.Testing
dotnet add src/Tools/CodegenCS.Tools.CliTool.Tests/CodegenCS.Tools.CliTool.Tests.csproj \
    package Testably.Abstractions.Testing
dotnet add src/SourceGenerator/CodegenCS.SourceGenerator.Tests/CodegenCS.SourceGenerator.Tests.csproj \
    package Testably.Abstractions.Testing
```

### Phase 2: Update Production Code (Days 2-3)

**Add IFileSystem to constructors**:
```csharp
// Before:
public class TemplateLauncher
{
    public TemplateLauncher(/* existing params */)
    {
        // Uses System.IO directly
    }
}

// After:
public class TemplateLauncher
{
    private readonly IFileSystem _fileSystem;
    
    public TemplateLauncher(/* existing params */, IFileSystem? fileSystem = null)
    {
        _fileSystem = fileSystem ?? new FileSystem(); // Default to real file system
    }
}
```

**Replace System.IO calls**:
```csharp
// Before:
var content = File.ReadAllText(templatePath);
if (!Directory.Exists(outputDir))
    Directory.CreateDirectory(outputDir);
var outputPath = Path.Combine(outputDir, "output.cs");
File.WriteAllText(outputPath, generatedCode);

// After:
var content = _fileSystem.File.ReadAllText(templatePath);
if (!_fileSystem.Directory.Exists(outputDir))
    _fileSystem.Directory.CreateDirectory(outputDir);
var outputPath = _fileSystem.Path.Combine(outputDir, "output.cs");
_fileSystem.File.WriteAllText(outputPath, generatedCode);
```

### Phase 3: Update Test Infrastructure (Day 3)

**Update BaseTest classes**:
```csharp
// src/Core/CodegenCS.Tests/BaseTest.cs
public abstract class BaseTest
{
    protected IFileSystem FileSystem { get; private set; } = null!;
    
    [SetUp]
    public void BaseSetUp()
    {
        // Use in-memory file system for tests
        FileSystem = new MockFileSystem();
    }
}
```

**Cross-platform test pattern**:
```csharp
[Test]
public void TestWindowsBehaviorOnLinux()
{
    // Simulate Windows file system
    var windowsFs = new MockFileSystem(o => o.SimulatingOperatingSystem(OSPlatform.Windows));
    var launcher = new TemplateLauncher(/* params */, windowsFs);
    
    windowsFs.File.WriteAllText(@"C:\Templates\template.csx", "template");
    launcher.Execute(@"C:\Templates\template.csx");
    
    // Case-insensitive check (Windows behavior)
    Assert.That(windowsFs.File.Exists(@"C:\OUTPUT\generated.cs"), Is.True);
}

[Test]
public void TestLinuxBehaviorOnWindows()
{
    // Simulate Linux file system
    var linuxFs = new MockFileSystem(o => o.SimulatingOperatingSystem(OSPlatform.Linux));
    var launcher = new TemplateLauncher(/* params */, linuxFs);
    
    linuxFs.File.WriteAllText("/home/templates/template.csx", "template");
    launcher.Execute("/home/templates/template.csx");
    
    // Case-sensitive check (Linux behavior)
    Assert.That(linuxFs.File.Exists("/home/OUTPUT/generated.cs"), Is.False);
    Assert.That(linuxFs.File.Exists("/home/output/generated.cs"), Is.True);
}
```

### Phase 4: Migration Strategy (Days 4-7)

**Priority Order**:
1. ✅ **Core libraries first** (CodegenCS, CodegenCS.Runtime)
   - Most used, foundational code
   - Benefits cascade to all dependent projects

2. ✅ **Tools next** (TemplateLauncher, TemplateBuilder)
   - Heavy file I/O usage
   - Critical for cross-platform consistency

3. ✅ **Tests immediately after** (update as production code changes)
   - Fix hardcoded path separators
   - Add cross-platform test cases
   - Update snapshot tests

4. ⏸️ **Models later** (DbSchema.Extractor, etc.)
   - Less file I/O
   - Can migrate gradually

**Migration Checklist per Project**:
- [ ] Add Testably.Abstractions package reference
- [ ] Add IFileSystem parameter to constructors (optional, defaults to `new FileSystem()`)
- [ ] Replace all `File.*` calls with `_fileSystem.File.*`
- [ ] Replace all `Directory.*` calls with `_fileSystem.Directory.*`
- [ ] Replace all `Path.*` calls with `_fileSystem.Path.*`
- [ ] Update tests to use MockFileSystem
- [ ] Add cross-platform test cases (Windows behavior on Linux, vice versa)
- [ ] Update documentation

### Benefits of Full Integration

**For Production**:
- ✅ Consistent file system behavior across platforms
- ✅ Proven edge case handling (path lengths, invalid chars, symlinks)
- ✅ Future-proof (maintained library, frequent updates)
- ✅ Dependency injection friendly
- ✅ Easier to test file system errors (permissions, disk full)

**For Testing**:
- ✅ **Critical**: Test Windows behavior on Linux (and vice versa)
- ✅ Fast in-memory tests (10-100x faster)
- ✅ No cleanup needed (automatic)
- ✅ Isolated tests (no shared state)
- ✅ Simulate file system errors easily

**For Project Maintenance**:
- ✅ No custom implementation to maintain
- ✅ Community support and bug fixes
- ✅ Regular updates for new .NET versions
- ✅ Comprehensive documentation

**Timeline**: 1 week for full integration vs 2+ weeks for custom implementation
**Risk**: Low (proven library) vs High (custom implementation bugs)
**Benefit**: Complete cross-platform testing capability essential for CodegenCS

### Addressing the Drawbacks

**External Dependency**:
- ✅ Acceptable: CodegenCS already has dependencies (Newtonsoft.Json, NSwag, etc.)
- ✅ Testably.Abstractions is well-maintained and stable
- ✅ ~100KB is negligible for a code generation tool

**Larger API Surface**:
- ✅ Use only what you need - the rest is available if requirements grow
- ✅ Better to have comprehensive coverage than discover missing features later

**Learning Curve**:
- ✅ API is identical to System.IO - minimal learning needed
- ✅ Good documentation and examples available
- ✅ IntelliSense works perfectly

## Integration Tests and File System Abstraction

### Unit Tests vs Integration Tests

**Unit Tests** (CodegenCS.Tests):
- Should use `MockFileSystem` for fast, isolated testing
- All file operations in-memory
- Can test both Windows and Linux behavior on any platform
- No cleanup needed
- **File system abstraction is beneficial**

**Integration Tests** (SourceGenerator.Tests, CliTool.Tests):
- May need **real file system** for accurate platform testing
- Test actual build processes, executable invocation, etc.
- Validate real MSBuild/Roslyn behavior
- Test real process spawning and I/O
- **File system abstraction may be limiting**

### Integration Test Considerations

#### SourceGenerator.Tests

**Challenge**: These tests invoke `dotnet build` which:
- Uses MSBuild (expects real file system)
- Invokes Roslyn (reads .csproj from disk)
- Generates actual assemblies
- Cannot be mocked with in-memory file system

**Recommendation**:
```csharp
public class CodegenGeneratorIntegrationTests
{
    // DON'T inject IFileSystem - use real file system
    // These are integration tests validating real build behavior
    
    [Test]
    public void SourceGenerator1_BuildSucceeds_OnCurrentPlatform()
    {
        // Uses actual File.Exists, Directory.GetFiles, etc.
        var projectPath = Path.Combine(_samplesPath, "SourceGenerator1.csproj");
        var (exitCode, output) = RunDotNetBuild(projectPath);
        
        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(File.Exists(expectedOutput), Is.True);
    }
}
```

**Rationale**:
- Integration tests validate **real system behavior**
- MSBuild cannot read from MockFileSystem
- Platform differences should be observed, not mocked
- Use temp directories and cleanup for isolation

#### CliTool.Tests

**Challenge**: These tests spawn `dotnet-codegencs` executable:
- Process expects real file system paths
- Cannot pass MockFileSystem to external process
- Tests download templates (network I/O)
- Validates real CLI workflow

**Recommendation**:
```csharp
public class BasicTests : BaseTest
{
    // DON'T inject IFileSystem for integration tests
    // Use real file system with proper cleanup
    
    [Test]
    [Category("Integration")]
    [Category("RequiresNetwork")]
    public async Task CloneByFullUrl()
    {
        // Uses real File.Exists, spawns real process
        var result = await Run("template clone https://...");
        
        Assert.That(result.ExitCode, Is.EqualTo(0));
        FileAssert.Exists("SimplePocos.cs"); // Real file system
    }
    
    [TearDown]
    public void Cleanup()
    {
        // Clean up real files after test
        if (File.Exists("SimplePocos.cs"))
            File.Delete("SimplePocos.cs");
    }
}
```

**Rationale**:
- External processes cannot access MockFileSystem
- Real file I/O needed for accurate integration testing
- Platform differences emerge naturally
- Cleanup in teardown ensures isolation

### Hybrid Approach: Best of Both Worlds

**Unit Tests** → Use MockFileSystem:
```csharp
// CodegenCS.Tests (unit tests)
[SetUp]
public void Setup()
{
    FileSystem = new MockFileSystem(); // Fast, isolated
}

[Test]
public void GeneratesCorrectOutput()
{
    var context = new CodegenContext(FileSystem);
    // Test logic only, no real I/O
}
```

**Integration Tests** → Use Real File System:
```csharp
// SourceGenerator.Tests, CliTool.Tests (integration tests)
[SetUp]
public void Setup()
{
    // Don't inject file system - use System.IO directly
    _testDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
    Directory.CreateDirectory(_testDir);
}

[TearDown]
public void Cleanup()
{
    if (Directory.Exists(_testDir))
        Directory.Delete(_testDir, recursive: true);
}

[Test]
[Category("Integration")]
public void RealBuildProcess()
{
    // Uses real file system, real MSBuild, real processes
}
```

### Migration Strategy for Test Projects

**Phase 1**: Unit tests first
- [ ] Update CodegenCS.Tests to use MockFileSystem
- [ ] Migrate BaseTest.cs for unit tests
- [ ] Add cross-platform unit test cases

**Phase 2**: Keep integration tests on real file system
- [ ] SourceGenerator.Tests uses System.IO directly
- [ ] CliTool.Tests uses System.IO directly
- [ ] Add proper cleanup in [TearDown]
- [ ] Use temp directories for isolation

**Phase 3**: Production code can support both
- [ ] Inject IFileSystem with default `new FileSystem()`
- [ ] Unit tests pass MockFileSystem
- [ ] Integration tests use default (real file system)

### Key Insight

**File system abstraction is valuable for unit tests (fast, isolated, cross-platform simulation) but may be counterproductive for integration tests that need to validate real system behavior.**

Integration tests should:
- ✅ Use real file system to expose platform differences
- ✅ Test actual build tooling (MSBuild, Roslyn)
- ✅ Spawn real processes with real I/O
- ✅ Use proper cleanup for isolation
- ❌ Don't mock what you're trying to validate