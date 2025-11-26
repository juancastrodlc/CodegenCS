using System;
using System.IO.Abstractions;

namespace CodegenCS.IO
{
    public static class Pathy
    {
        internal static IPath CurrentPath {get; private set;}
        public static void Reset()
        {
            CurrentPath=null;
        }

        public static char AltDirectorySeparatorChar => throw new NotImplementedException();

        public static char DirectorySeparatorChar => throw new NotImplementedException();

        public static char PathSeparator => throw new NotImplementedException();

        public static char VolumeSeparatorChar => throw new NotImplementedException();

        public static IFileSystem FileSystem => throw new NotImplementedException();

        public static string ChangeExtension(string path, string extension)
        {
            throw new NotImplementedException();
        }

        public static string Combine(string path1, string path2)
        {
            throw new NotImplementedException();
        }

        public static string Combine(string path1, string path2, string path3)
        {
            throw new NotImplementedException();
        }

        public static string Combine(string path1, string path2, string path3, string path4)
        {
            throw new NotImplementedException();
        }

        public static string Combine(params string[] paths)
        {
            throw new NotImplementedException();
        }

        public static string GetDirectoryName(string path)
        {
            throw new NotImplementedException();
        }

        public static string GetExtension(string path)
        {
            throw new NotImplementedException();
        }

        public static string GetFileName(string path)
        {
            throw new NotImplementedException();
        }

        public static string GetFileNameWithoutExtension(string path)
        {
            throw new NotImplementedException();
        }

        public static string GetFullPath(string path)
        {
            throw new NotImplementedException();
        }

        public static char[] GetInvalidFileNameChars()
        {
            throw new NotImplementedException();
        }

        public static char[] GetInvalidPathChars()
        {
            throw new NotImplementedException();
        }

        public static string GetPathRoot(string path)
        {
            throw new NotImplementedException();
        }

        public static string GetRandomFileName()
        {
            throw new NotImplementedException();
        }

        public static string GetTempFileName()
        {
            throw new NotImplementedException();
        }

        public static string GetTempPath()
        {
            throw new NotImplementedException();
        }

        public static bool HasExtension(string path)
        {
            throw new NotImplementedException();
        }

        public static bool IsPathRooted(string path)
        {
            throw new NotImplementedException();
        }

        public class TestablePath : IPath
        {
            IPath path;
            public TestablePath(IPath path)
            {
                this.path=path;
                CurrentPath=this;
            }

            public char AltDirectorySeparatorChar => throw new NotImplementedException();

            public char DirectorySeparatorChar => throw new NotImplementedException();

            public char PathSeparator => throw new NotImplementedException();

            public char VolumeSeparatorChar => throw new NotImplementedException();

            public IFileSystem FileSystem => throw new NotImplementedException();

            public string ChangeExtension(string path, string extension)
            {
                throw new NotImplementedException();
            }

            public string Combine(string path1, string path2)
            {
                throw new NotImplementedException();
            }

            public string Combine(string path1, string path2, string path3)
            {
                throw new NotImplementedException();
            }

            public string Combine(string path1, string path2, string path3, string path4)
            {
                throw new NotImplementedException();
            }

            public string Combine(params string[] paths)
            {
                throw new NotImplementedException();
            }

            public bool EndsInDirectorySeparator(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public bool EndsInDirectorySeparator(string path)
            {
                throw new NotImplementedException();
            }

            public bool Exists(string path)
            {
                throw new NotImplementedException();
            }

            public string GetDirectoryName(string path)
            {
                throw new NotImplementedException();
            }

            public ReadOnlySpan<char> GetDirectoryName(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public string GetExtension(string path)
            {
                throw new NotImplementedException();
            }

            public ReadOnlySpan<char> GetExtension(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public string GetFileName(string path)
            {
                throw new NotImplementedException();
            }

            public ReadOnlySpan<char> GetFileName(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public string GetFileNameWithoutExtension(string path)
            {
                throw new NotImplementedException();
            }

            public ReadOnlySpan<char> GetFileNameWithoutExtension(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public string GetFullPath(string path)
            {
                throw new NotImplementedException();
            }

            public string GetFullPath(string path, string basePath)
            {
                throw new NotImplementedException();
            }

            public char[] GetInvalidFileNameChars()
            {
                throw new NotImplementedException();
            }

            public char[] GetInvalidPathChars()
            {
                throw new NotImplementedException();
            }

            public string GetPathRoot(string path)
            {
                throw new NotImplementedException();
            }

            public ReadOnlySpan<char> GetPathRoot(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public string GetRandomFileName()
            {
                throw new NotImplementedException();
            }

            public string GetRelativePath(string relativeTo, string path)
            {
                throw new NotImplementedException();
            }

            public string GetTempFileName()
            {
                throw new NotImplementedException();
            }

            public string GetTempPath()
            {
                throw new NotImplementedException();
            }

            public bool HasExtension(string path)
            {
                throw new NotImplementedException();
            }

            public bool HasExtension(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public bool IsPathFullyQualified(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public bool IsPathFullyQualified(string path)
            {
                throw new NotImplementedException();
            }

            public bool IsPathRooted(string path)
            {
                throw new NotImplementedException();
            }

            public bool IsPathRooted(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public string Join(ReadOnlySpan<char> path1, ReadOnlySpan<char> path2)
            {
                throw new NotImplementedException();
            }

            public string Join(ReadOnlySpan<char> path1, ReadOnlySpan<char> path2, ReadOnlySpan<char> path3)
            {
                throw new NotImplementedException();
            }

            public string Join(ReadOnlySpan<char> path1, ReadOnlySpan<char> path2, ReadOnlySpan<char> path3, ReadOnlySpan<char> path4)
            {
                throw new NotImplementedException();
            }

            public string Join(string path1, string path2)
            {
                throw new NotImplementedException();
            }

            public string Join(string path1, string path2, string path3)
            {
                throw new NotImplementedException();
            }

            public string Join(string path1, string path2, string path3, string path4)
            {
                throw new NotImplementedException();
            }

            public string Join(params string[] paths)
            {
                throw new NotImplementedException();
            }

            public ReadOnlySpan<char> TrimEndingDirectorySeparator(ReadOnlySpan<char> path)
            {
                throw new NotImplementedException();
            }

            public string TrimEndingDirectorySeparator(string path)
            {
                throw new NotImplementedException();
            }

            public bool TryJoin(ReadOnlySpan<char> path1, ReadOnlySpan<char> path2, Span<char> destination, out int charsWritten)
            {
                throw new NotImplementedException();
            }

            public bool TryJoin(ReadOnlySpan<char> path1, ReadOnlySpan<char> path2, ReadOnlySpan<char> path3, Span<char> destination, out int charsWritten)
            {
                throw new NotImplementedException();
            }
        }
    }
}