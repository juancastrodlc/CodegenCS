using System;
using System.IO;
using System.Net;

namespace CodegenCS.TemplateDownloader
{
    /// <summary>
    /// Location of the CodegenCS Templates repository (https://github.com/CodegenCS/Templates).
    /// By default templates are downloaded from GitHub, but the environment variable <see cref="EnvironmentVariable"/>
    /// can point to a mirror: another URI or a local directory (useful for offline environments).
    /// Local mirrors may keep the repository structure (e.g. DatabaseSchema/SimplePocos/SimplePocos.cs) or be flat (SimplePocos.cs).
    /// </summary>
    public static class TemplatesRepository
    {
        public const string EnvironmentVariable = "CODEGENCS_TEMPLATES_URI";
        public const string DefaultUri = "https://raw.githubusercontent.com/CodegenCS/Templates/main/";
        public const string CatalogFile = "templates-index.json";

        public static string BaseUri
        {
            get
            {
                var value = Environment.GetEnvironmentVariable(EnvironmentVariable);
                return string.IsNullOrWhiteSpace(value) ? DefaultUri : value.Trim();
            }
        }

        public static bool IsLocal => IsLocalLocation(BaseUri);

        public static string LocalDirectory => IsLocal ? ToLocalPath(BaseUri) : null;

        /// <summary>
        /// Resolves a path relative to the root of the Templates repository (e.g. "DatabaseSchema/SimplePocos/SimplePocos.cs")
        /// </summary>
        public static string Resolve(string relativePath)
        {
            relativePath = (relativePath ?? "").Replace('\\', '/').TrimStart('/');
            if (!IsLocal)
                return BaseUri.TrimEnd('/') + "/" + relativePath;

            var directory = LocalDirectory;
            var structured = Path.GetFullPath(Path.Combine(directory, relativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (File.Exists(structured))
                return structured;
            var flat = Path.Combine(directory, Path.GetFileName(relativePath));
            return File.Exists(flat) ? flat : structured;
        }

        /// <summary>
        /// If the location points to the default (GitHub) Templates repository it's redirected to the configured repository.
        /// </summary>
        public static string Rebase(string location)
        {
            if (location != null && location.StartsWith(DefaultUri, StringComparison.OrdinalIgnoreCase))
                return Resolve(location.Substring(DefaultUri.Length));
            return location;
        }

        public static bool IsLocalLocation(string location) =>
            !(location.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || location.StartsWith("https://", StringComparison.OrdinalIgnoreCase));

        public static string ReadAllText(string location)
        {
            if (IsLocalLocation(location))
                return File.ReadAllText(ToLocalPath(location));
            using (var client = new WebClient())
                return client.DownloadString(location);
        }

        public static void Download(string location, string targetFile)
        {
            if (IsLocalLocation(location))
            {
                File.Copy(ToLocalPath(location), targetFile, overwrite: true);
                return;
            }
            using (var client = new WebClient())
                client.DownloadFile(location, targetFile);
        }

        private static string ToLocalPath(string location) =>
            location.StartsWith("file:", StringComparison.OrdinalIgnoreCase) ? new Uri(location).LocalPath : Path.GetFullPath(location);
    }
}
