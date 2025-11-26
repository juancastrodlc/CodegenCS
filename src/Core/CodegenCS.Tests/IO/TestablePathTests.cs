using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using NUnit.Framework;
using System.IO.Abstractions;
using CodegenCS.IO;
using Testably.Abstractions.Testing;

namespace CodegenCS.Tests.IO
{
    public class TestablePathTests
    {
        Pathy.TestablePath testablePath;
        IFileSystem mockFileSystem;
        [SetUp]
        public void Setup()
        {
            mockFileSystem = new MockFileSystem();
            mockFileSystem
                .Initialize()
                .WithSubdirectory("src")
                .Initialized(d => d.WithFile("Program.cs"))
                .WithSubdirectory("tests")
                .Initialized(d => d.WithFile("Tests.cs"))
                .WithFile("README.md");
            testablePath = new Pathy.TestablePath(mockFileSystem.Path);
        }

    }
}