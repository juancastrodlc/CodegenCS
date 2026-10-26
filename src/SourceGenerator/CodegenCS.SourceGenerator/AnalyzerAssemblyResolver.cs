using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;

namespace CodegenCS.CodeGenerator
{
    internal static class AnalyzerAssemblyResolver
    {
        private static int _registered;
        private static readonly Dictionary<string, Assembly> _loadedTemplates = new Dictionary<string, Assembly>(StringComparer.Ordinal);
        [ThreadStatic]
        private static bool _resolving;
        private static readonly Assembly _ownAssembly = typeof(AnalyzerAssemblyResolver).Assembly;
        private static readonly Type _loadContextType = Type.GetType("System.Runtime.Loader.AssemblyLoadContext, System.Runtime.Loader", throwOnError: false);

        public static void EnsureRegistered()
        {
            if (Interlocked.Exchange(ref _registered, 1) == 1)
                return;
            TemplateBuilder.RoslynCompiler.AssemblyLocationResolver = GetLocation;
            TemplateLauncher.TemplateLauncher.TemplateAssemblyLoader = LoadTemplate;
            AppDomain.CurrentDomain.AssemblyResolve += Resolve;
        }

        public static string OwnDirectory
        {
            get
            {
                var location = GetLocation(_ownAssembly);
                return string.IsNullOrEmpty(location) ? null : Path.GetDirectoryName(location);
            }
        }

        public static Assembly LoadTemplate(string path)
        {
            var ownContext = GetOwnLoadContext();
            if (ownContext == null)
                return null;
            lock (_loadedTemplates)
            {
                if (_loadedTemplates.TryGetValue(path, out var cached))
                    return cached;
                var name = AssemblyName.GetAssemblyName(path).Name;
                var assembly = LoadedAssemblies(ownContext).FirstOrDefault(a => a.GetName().Name == name)
                    ?? (Assembly)_loadContextType.GetMethod("LoadFromAssemblyPath", new[] { typeof(string) }).Invoke(ownContext, new object[] { path });
                _loadedTemplates[path] = assembly;
                return assembly;
            }
        }

        public static string GetLocation(Assembly assembly)
        {
            string location = null;
            try
            {
                location = assembly.Location;
            }
            catch (NotSupportedException)
            {
            }
            if (!string.IsNullOrEmpty(location))
                return location;

            var directory = GetLoadContextDirectory(assembly);
            if (directory != null)
            {
                var candidate = Path.Combine(directory, assembly.GetName().Name + ".dll");
                if (File.Exists(candidate))
                    return candidate;
            }
            return location;
        }

        private static string GetLoadContextDirectory(Assembly assembly)
        {
            if (_loadContextType == null)
                return null;
            var loadContext = _loadContextType.GetMethod("GetLoadContext", new[] { typeof(Assembly) })?.Invoke(null, new object[] { assembly });
            var property = loadContext?.GetType().GetProperty("Directory", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            return property?.GetValue(loadContext) as string;
        }

        private static Assembly Resolve(object sender, ResolveEventArgs args)
        {
            if (_resolving)
                return null;
            _resolving = true;
            try
            {
                return ResolveCore(args);
            }
            finally
            {
                _resolving = false;
            }
        }

        private static Assembly ResolveCore(ResolveEventArgs args)
        {
            AssemblyName requested;
            try
            {
                requested = new AssemblyName(args.Name);
            }
            catch (ArgumentException)
            {
                return null;
            }

            if (string.Equals(requested.Name, _ownAssembly.GetName().Name, StringComparison.OrdinalIgnoreCase))
                return _ownAssembly;

            var ownContext = GetOwnLoadContext();
            var loaded = LoadedAssemblies(ownContext).FirstOrDefault(a => string.Equals(a.GetName().Name, requested.Name, StringComparison.OrdinalIgnoreCase));
            if (loaded != null)
                return loaded;

            var directory = OwnDirectory;
            if (directory == null || !File.Exists(Path.Combine(directory, requested.Name + ".dll")))
                return null;

            try
            {
                if (ownContext != null)
                    return (Assembly)_loadContextType.GetMethod("LoadFromAssemblyName", new[] { typeof(AssemblyName) }).Invoke(ownContext, new object[] { requested });
                return Assembly.LoadFrom(Path.Combine(directory, requested.Name + ".dll"));
            }
            catch (Exception)
            {
                return null;
            }
        }

        private static object GetOwnLoadContext()
        {
            if (_loadContextType == null)
                return null;
            return _loadContextType.GetMethod("GetLoadContext", new[] { typeof(Assembly) })?.Invoke(null, new object[] { _ownAssembly });
        }

        private static IEnumerable<Assembly> LoadedAssemblies(object loadContext)
        {
            if (loadContext != null && _loadContextType.GetProperty("Assemblies")?.GetValue(loadContext) is IEnumerable<Assembly> assemblies)
                return assemblies;
            return AppDomain.CurrentDomain.GetAssemblies();
        }
    }
}
