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

### Updated Recommendation

**Use Testably.Abstractions.Testing** for test projects only:

**Hybrid Approach**:
1. **Production Code**: Keep using `System.IO` directly
   - No abstraction layer in production
   - Zero runtime overhead
   - No dependency in distributed packages

2. **Test Code**: Use Testably.Abstractions
   - Add only to test projects (`*.Tests.csproj`)
   - Not included in NuGet packages
   - Only affects development/testing

**Benefits of Hybrid**:
- ✅ No production dependencies
- ✅ Proven cross-platform mocking
- ✅ Fast in-memory tests
- ✅ Test Windows behavior on Linux
- ✅ Test Linux behavior on Windows
- ✅ No need to build custom mocking

**Implementation**:
```bash
# Add ONLY to test projects
dotnet add src/Core/CodegenCS.Tests/CodegenCS.Tests.csproj \
    package Testably.Abstractions.Testing
dotnet add src/Tools/CodegenCS.Tools.CliTool.Tests/CodegenCS.Tools.CliTool.Tests.csproj \
    package Testably.Abstractions.Testing

# Production projects - NO changes needed
# Keep using System.IO.File, System.IO.Directory, System.IO.Path directly
```

**Test Code Pattern**:
```csharp
[Test]
public void TestCrossPlatform()
{
    // Test Windows behavior on Linux
    var windowsFs = new MockFileSystem(o => o.SimulatingOperatingSystem(OSPlatform.Windows));
    windowsFs.File.WriteAllText(@"C:\Users\test\file.txt", "content");
    Assert.That(windowsFs.File.Exists(@"C:\users\TEST\FILE.TXT"), Is.True); // Case-insensitive
    
    // Test Linux behavior on Windows
    var linuxFs = new MockFileSystem(o => o.SimulatingOperatingSystem(OSPlatform.Linux));
    linuxFs.File.WriteAllText("/home/test/file.txt", "content");
    Assert.That(linuxFs.File.Exists("/home/test/FILE.TXT"), Is.False); // Case-sensitive
}
```

### Revised Recommendation

**DON'T implement custom abstraction** - complexity is deceptive

**DO use Testably.Abstractions.Testing for tests**:
- Mature, battle-tested (15,000+ LOC is a feature, not a bug)
- Handles edge cases you haven't thought of
- Only in test projects (dev dependency)
- No production impact

**Timeline**: 1 day to add and configure vs 2+ weeks to implement correctly
**Risk**: Low (isolated to tests) vs High (subtle platform bugs)
**Benefit**: Proven cross-platform testing without production dependencies
