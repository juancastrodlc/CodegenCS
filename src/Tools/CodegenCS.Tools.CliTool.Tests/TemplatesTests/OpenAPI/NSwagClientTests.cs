using DependencyContainer = CodegenCS.Utils.DependencyContainer;
using NUnit.Framework;
using System;
using System.IO;
using System.Threading.Tasks;
using System.Linq;
using System.Text;
using System.Net;
using NUnit.Framework.Legacy;
using Assert = NUnit.Framework.Legacy.ClassicAssert;


namespace CodegenCS.Tools.CliTool.Tests
{
    internal class NSwagClientTests : BaseTest
    {
        [OneTimeSetUp]
        #region Download Templates and Models
        public async Task DownloadSampleModels()
        {
            await base.Setup();
            string[] templatesToClone = new string[] { "NSwagClient" };

            string[] modelsToDownload = new string[]
            {
                OnlineSources.PetstoreOpenApiUrl
            };

            foreach (var templateAlias in templatesToClone)
            {
                if (File.Exists($"{templateAlias}.dll"))
                    File.Delete($"{templateAlias}.dll");
                if (File.Exists($"{templateAlias}.cs"))
                    File.Delete($"{templateAlias}.cs");

                var result = await Run($"template clone {templateAlias}");
                Assert.AreEqual(0, result.ExitCode, _stdOut + _stdErr);
                FileAssert.Exists($"{templateAlias}.cs");
                FileAssert.Exists($"{templateAlias}.dll");
            }

            foreach (var url in modelsToDownload)
            {
                string localPath = OnlineSources.LocalFileName(url);
                if (File.Exists(localPath))
                    File.Delete(localPath);
                await OnlineSources.DownloadAsync(url, localPath);
                FileAssert.Exists(localPath);
            }

        }
        #endregion

        #region Checking if template output matches the previous snapshot (no breaking changes)
        [TestCase("NSwagClient", "petstore-openapi3.json")]
        public async Task TestTemplate(string templateAlias, string model)
        {
            string cmd = $"template run {templateAlias}.dll {model} MyNamespace";
            
            var result = await Run(cmd);
            Assert.AreEqual(0, result.ExitCode);

            // Debug:
            //var result = await new TemplateCliArgsTests().LaunchAsync($"{templateAlias}.dll", new string[] { model }, new string[] { "MyNamespace" });
            //Assert.AreEqual(0, result);

            StringAssert.Contains($"Loading '{templateAlias}.dll'...", _stdOut);
            StringAssert.Contains("Model type is 'NSwag.OpenApiDocument'...", _stdOut);
            StringAssert.Contains($"Model successfully loaded from '{model}'...", _stdOut);
            StringAssert.Contains($"Successfully executed template '{templateAlias}.dll'.", _stdOut);
            StringAssert.AreEqualIgnoringCase(string.Empty, _stdErr);
            FileAssert.Exists($"{templateAlias}.g.cs");
            string snapshot = Path.Combine(GetSourceFileFolder(), "Snapshots", "petstore-openapi3.g.cs");
            var snapshotText = File.ReadAllText(snapshot).ReplaceLineEndings();
            var templateText = File.ReadAllText($"{templateAlias}.g.cs");//.ReplaceLineEndings();
            Assert.AreEqual(snapshotText, templateText);            
        }
        #endregion




    }
}
