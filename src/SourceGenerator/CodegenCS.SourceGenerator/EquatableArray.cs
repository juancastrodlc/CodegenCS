using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;

namespace CodegenCS.CodeGenerator
{
    /// <summary>
    /// Immutable array with value equality, so it can be safely used as an incremental generator pipeline value.
    /// </summary>
    internal readonly struct EquatableArray<T> : IEquatable<EquatableArray<T>>, IEnumerable<T>
        where T : IEquatable<T>
    {
        private readonly T[] _items;

        public EquatableArray(IEnumerable<T> items)
        {
            _items = items?.ToArray() ?? new T[0];
        }

        public int Count => _items?.Length ?? 0;

        public bool Equals(EquatableArray<T> other) =>
            (_items ?? new T[0]).SequenceEqual(other._items ?? new T[0]);

        public override bool Equals(object obj) => obj is EquatableArray<T> other && Equals(other);

        public override int GetHashCode()
        {
            unchecked
            {
                int hash = 17;
                foreach (var item in this)
                    hash = hash * 31 + (item?.GetHashCode() ?? 0);
                return hash;
            }
        }

        public IEnumerator<T> GetEnumerator() => ((IEnumerable<T>)(_items ?? new T[0])).GetEnumerator();

        IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
    }
}
