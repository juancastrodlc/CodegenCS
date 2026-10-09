using CodegenCS.Utils;
using System;
using System.Collections.Generic;
using System.CommandLine;
using System.Linq;
using System.Reflection;
using static CodegenCS.Utils.DependencyContainer;

namespace CodegenCS.Runtime
{
    /// <summary>
    /// Resolves IAutoBindCommandLineArgs types from matching command-line arguments and options.
    /// </summary>
    public class AutoBindCommandLineArgsTypeResolver : ITypeResolver
    {
        private static readonly MethodInfo GetArgumentValue = typeof(ParseResult).GetMethods()
            .Single(method => method.Name == "GetValue" &&
                              method.IsGenericMethodDefinition &&
                              method.GetParameters().Length == 1 &&
                              method.GetParameters()[0].ParameterType.IsGenericType &&
                              method.GetParameters()[0].ParameterType.GetGenericTypeDefinition() == typeof(Argument<>));

        private static readonly MethodInfo GetOptionValue = typeof(ParseResult).GetMethods()
            .Single(method => method.Name == "GetValue" &&
                              method.IsGenericMethodDefinition &&
                              method.GetParameters().Length == 1 &&
                              method.GetParameters()[0].ParameterType.IsGenericType &&
                              method.GetParameters()[0].ParameterType.GetGenericTypeDefinition() == typeof(Option<>));

        public bool CanResolveType(Type targetType)
        {
            return typeof(IAutoBindCommandLineArgs).IsAssignableFrom(targetType);
        }

        public bool TryResolveType(Type targetType, DependencyContainer dependencyContainer, out object value)
        {
            ParseResult parseResult;
            try
            {
                parseResult = (ParseResult)dependencyContainer.Resolve(typeof(ParseResult));
            }
            catch (InvalidOperationException ex) when (ex.Message.Contains("ParseResult is not registered"))
            {
                value = null;
                return false;
            }

            value = Activator.CreateInstance(targetType);
            var commands = GetCommands(parseResult.RootCommandResult.Command);
            var symbols = commands.SelectMany(command => command.Arguments.Cast<Symbol>().Concat(command.Options));

            foreach (var property in targetType.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                         .Where(property => property.CanWrite && property.GetIndexParameters().Length == 0))
            {
                var symbol = symbols.FirstOrDefault(candidate => Matches(candidate, property.Name));
                if (symbol == null)
                    continue;

                if (parseResult.GetResult(symbol) == null)
                    continue;

                var getter = symbol is Argument
                    ? GetArgumentValue
                    : GetOptionValue;
                var typedGetter = getter.MakeGenericMethod(property.PropertyType);
                var propertyValue = typedGetter.Invoke(parseResult, new[] { symbol });
                property.SetValue(value, propertyValue);
            }

            return true;
        }

        private static bool Matches(Symbol symbol, string propertyName)
        {
            if (string.Equals(symbol.Name, propertyName, StringComparison.OrdinalIgnoreCase))
                return true;

            return symbol is Option option && (MatchesName(option.Name, propertyName) ||
                option.Aliases.Any(alias => MatchesName(alias, propertyName)));
        }

        private static bool MatchesName(string name, string propertyName)
        {
            var symbolName = name.TrimStart('-', '/');
            var prefixSeparator = symbolName.LastIndexOf(':');
            if (prefixSeparator >= 0)
                symbolName = symbolName.Substring(prefixSeparator + 1);
            return string.Equals(symbolName, propertyName, StringComparison.OrdinalIgnoreCase);
        }

        private static IEnumerable<Command> GetCommands(Command command)
        {
            yield return command;
            foreach (var child in command.Subcommands)
            {
                foreach (var descendant in GetCommands(child))
                    yield return descendant;
            }
        }
    }
}
