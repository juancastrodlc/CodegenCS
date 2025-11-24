using System.IO.Abstractions;

namespace CodegenCS.IO
{
    public static class FileSystem
    {
        internal static IFileSystem CurrentFileSystem { get; private set; }

        public static IDirectory Directory => CurrentFileSystem.Directory;

        public static IDirectoryInfoFactory DirectoryInfo => CurrentFileSystem.DirectoryInfo;

        public static IDriveInfoFactory DriveInfo => CurrentFileSystem.DriveInfo;

        public static IFile File => CurrentFileSystem.File;

        public static IFileInfoFactory FileInfo => CurrentFileSystem.FileInfo;

        public static IFileStreamFactory FileStream => CurrentFileSystem.FileStream;

        public static IFileSystemWatcherFactory FileSystemWatcher => CurrentFileSystem.FileSystemWatcher;

        public static IFileVersionInfoFactory FileVersionInfo => CurrentFileSystem.FileVersionInfo;

        public static IPath Path => CurrentFileSystem.Path;

        public class TestableFileSystem : IFileSystem
        {
            readonly IFileSystem fileSystem;
            public TestableFileSystem(IFileSystem fileSystem)
            {
                this.fileSystem= fileSystem;
                CurrentFileSystem = fileSystem;
            }

            public IDirectory Directory => fileSystem.Directory;

            public IDirectoryInfoFactory DirectoryInfo => fileSystem.DirectoryInfo;

            public IDriveInfoFactory DriveInfo => fileSystem.DriveInfo;

            public IFile File => fileSystem.File;

            public IFileInfoFactory FileInfo => fileSystem.FileInfo;

            public IFileStreamFactory FileStream => fileSystem.FileStream;

            public IFileSystemWatcherFactory FileSystemWatcher => fileSystem.FileSystemWatcher;

            public IFileVersionInfoFactory FileVersionInfo => fileSystem.FileVersionInfo;

            public IPath Path => fileSystem.Path;
        }
    }
}