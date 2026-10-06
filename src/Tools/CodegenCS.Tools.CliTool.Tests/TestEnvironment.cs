using NUnit.Framework;
using System;
using System.IO;

namespace CodegenCS.Tools.CliTool.Tests
{
    [SetUpFixture]
    public class TestEnvironment
    {
        public static string TestDirectory => Path.GetDirectoryName(typeof(DotNetTool.Program).Assembly.Location);

        [OneTimeSetUp]
        public void SetWorkingDirectory()
        {
            Directory.SetCurrentDirectory(TestDirectory);
        }
    }
}
