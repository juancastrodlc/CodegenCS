## Testably.Abstractions

These abstractions are one of the few cases in software engineering that justify a global state across the lifetime of an application, or across the context of a group of tests. I understand the rationale around System.IO being all static classes manipulating the OS environment and making their behaviour predictable in that way.

I think it is possible to do something that looks a lot like System.IO but it does not force all classes to have a member of the IFileSystem abstraction.

So I propose to have a class declared in namespace CodegenCS.IO which implements the IFileSystem interface and provide in that namespace Static wrappers around the different System.IO classes. The difference is that they should return the Interfaces they represent.

For example:

``` csharp
using CodgenCS.IO;

public class SomeClass
{
    IFileInfo fileInfo _myTemplate_cs;
    ... //
    public ProcessFile(string filePath,ContextClass context)
    {
        if (!File.Exists(filePath)) // this secretly does _fileSystem.FileExists(filePath); in a global singleton.
        {
            throw new FileDoesNotExistException(filePath);
        }
        _myTemplate_cs = FileInfo.New(); // calls _fileSistem.FileInfo.New();
        ...
        var outputFile = Path.Combine(Path.GetCurrentDirectory(),context.OutputDirectory,context.OutputFileName??Path.GetFileNamePart(context),context.Generated,context.Extension);
        outputFile = Path.SetExtension(filePath,context.outputExtension);
        ...
        // all the Path calls above did their corresponding calls to the _fileSystem
    }
}
```

This pattern simplifies migration in big files like CodegeneratorContext class definition.