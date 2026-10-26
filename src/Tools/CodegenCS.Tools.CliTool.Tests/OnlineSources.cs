using CodegenCS.TemplateDownloader;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Threading.Tasks;

namespace CodegenCS.Tools.CliTool.Tests
{
    /// <summary>
    /// Online resources used by the tests.
    /// By default they are downloaded from GitHub. To run the tests in an offline environment set the environment variable
    /// CODEGENCS_TEMPLATES_URI to a local mirror of https://github.com/CodegenCS/Templates (e.g. src/artifacts/OnlineTemplates).
    /// The same variable is honored by "dotnet-codegencs template clone".
    /// </summary>
    internal static class OnlineSources
    {
        public const string AdventureWorksSchemaUrl = "https://raw.githubusercontent.com/Drizin/CodegenCS/master/src/Models/CodegenCS.Models.DbSchema.SampleDatabases/AdventureWorksSchema.json";
        public const string PetstoreOpenApiUrl = TemplatesRepository.DefaultUri + "OpenAPI/SampleModels/petstore-openapi3.json";

        private static readonly Dictionary<string, string> _repositoryCopies = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            [AdventureWorksSchemaUrl] = "Models/CodegenCS.Models.DbSchema.SampleDatabases/AdventureWorksSchema.json",
            [PetstoreOpenApiUrl] = "Models/CodegenCS.Models.NSwagAdapter/SampleModels/petstore-openapi3.json",
        };

        public static bool IsOffline => TemplatesRepository.IsLocal;

        /// <summary>
        /// Location (as displayed by dotnet-codegencs) of a file in the Templates repository
        /// </summary>
        public static string TemplateLocation(string relativePath) => TemplatesRepository.Resolve(relativePath);

        public static string LocalFileName(string url) => url.Substring(url.LastIndexOf("/") + 1);

        public static async Task DownloadAsync(string url, string localPath)
        {
            if (!IsOffline)
            {
                using var client = new HttpClient();
                File.WriteAllBytes(localPath, await client.GetByteArrayAsync(url));
                return;
            }

            var candidates = new List<string> { TemplatesRepository.Rebase(url), Path.Combine(TemplatesRepository.LocalDirectory, LocalFileName(url)) };
            if (_repositoryCopies.TryGetValue(url, out var repositoryCopy))
                candidates.Add(Path.Combine(RepositorySrcDir, repositoryCopy.Replace('/', Path.DirectorySeparatorChar)));
            var source = candidates.FirstOrDefault(c => TemplatesRepository.IsLocalLocation(c) && File.Exists(c));
            if (source == null)
                throw new FileNotFoundException($"'{url}' is not available offline. Looked at: {string.Join(", ", candidates)}");
            File.Copy(source, localPath, overwrite: true);
        }

        private static string RepositorySrcDir =>
            typeof(OnlineSources).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>().Single(a => a.Key == "CodegenCS.RepositorySrcDir").Value;
    }
}
