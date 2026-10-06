using CodegenCS.Utils;
using NUnit.Framework;
using System;
using System.IO;

namespace CodegenCS.Tests.CoreTests
{
    public class IOUtilsTests
    {
        [Test]
        public void MakeRelativePath_ReturnsAbsolutePath_WhenTargetIsOutsideSourceDirectory()
        {
            string sourceDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString(), "source");
            string targetPath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString(), "output.dll");

            string result = IOUtils.MakeRelativePath(sourceDirectory, targetPath);

            Assert.AreEqual(Path.GetFullPath(targetPath), result);
        }

        [Test]
        public void MakeRelativePath_ReturnsRelativePath_WhenTargetIsInsideSourceDirectory()
        {
            string sourceDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
            string targetPath = Path.Combine(sourceDirectory, "nested", "output.dll");

            string result = IOUtils.MakeRelativePath(sourceDirectory, targetPath);

            Assert.AreEqual(Path.Combine("nested", "output.dll"), result);
        }
    }
}
