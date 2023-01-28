defmodule Mneme.Serialize do
  @moduledoc """
  Helpers for converting runtime values to match patterns.
  """

  alias Mneme.Serializer

  @doc """
  Generates a Mneme pattern expression from a runtime value.
  """
  @spec to_pattern(Serializer.t(), keyword()) :: Macro.t()
  def to_pattern(value, context \\ []) do
    case Serializer.to_pattern(value, context) do
      {pattern, nil} -> pattern
      {pattern, guard} -> {:when, [], [pattern, guard]}
    end
  end

  @doc """
  Returns `{:ok, pin_expr}` if the value can be found in the given
  binding, or `:error` otherwise.
  """
  def fetch_pinned(value, binding) do
    case List.keyfind(binding || [], value, 1) do
      {name, ^value} -> {:ok, {:^, [], [{name, [], nil}]}}
      _ -> :error
    end
  end

  @doc """
  Maps an enum of values to their match expressions, combining any
  guards into a single clause with `and`.
  """
  def enum_to_pattern(values, meta) do
    Enum.map_reduce(values, nil, fn value, guard ->
      case {guard, Serializer.to_pattern(value, meta)} do
        {nil, {expr, guard}} -> {expr, guard}
        {guard, {expr, nil}} -> {expr, guard}
        {guard1, {expr, guard2}} -> {expr, {:and, [], [guard1, guard2]}}
      end
    end)
  end

  @doc false
  def guard(name, guard) do
    var = {name, [], nil}
    {var, {guard, [], [var]}}
  end
end

defprotocol Mneme.Serializer do
  @fallback_to_any true

  @doc """
  Generates ASTs that can be used to assert a match of the given value.

  Must return `{match_expression, guard_expression}`, where the first
  will be used in a `=` match, and the second will be a secondary
  assertion with access to any bindings produced by the match.

  Note that `guard_expression` can be `nil`, in which case the guard
  check will not occur.
  """
  @spec to_pattern(t, keyword()) :: {Macro.t(), Macro.t() | nil}
  def to_pattern(value, meta)
end

defimpl Mneme.Serializer, for: Atom do
  def to_pattern(atom, _meta), do: {atom, nil}
end

defimpl Mneme.Serializer, for: Integer do
  def to_pattern(int, _meta), do: {int, nil}
end

defimpl Mneme.Serializer, for: Float do
  def to_pattern(float, _meta), do: {float, nil}
end

defimpl Mneme.Serializer, for: BitString do
  def to_pattern(str, _meta), do: {str, nil}
end

defimpl Mneme.Serializer, for: List do
  def to_pattern(list, meta) do
    Mneme.Serialize.enum_to_pattern(list, meta)
  end
end

defimpl Mneme.Serializer, for: Tuple do
  def to_pattern({a, b}, meta) do
    case {Mneme.Serializer.to_pattern(a, meta), Mneme.Serializer.to_pattern(b, meta)} do
      {{expr1, nil}, {expr2, nil}} -> {{expr1, expr2}, nil}
      {{expr1, guard}, {expr2, nil}} -> {{expr1, expr2}, guard}
      {{expr1, nil}, {expr2, guard}} -> {{expr1, expr2}, guard}
      {{expr1, guard1}, {expr2, guard2}} -> {{expr1, expr2}, {:and, [], [guard1, guard2]}}
    end
  end

  def to_pattern(tuple, meta) do
    values = Tuple.to_list(tuple)
    {value_matches, guard} = Mneme.Serialize.enum_to_pattern(values, meta)
    {{:{}, [], value_matches}, guard}
  end
end

defimpl Mneme.Serializer, for: Map do
  def to_pattern(map, meta) do
    {tuples, guard} = Mneme.Serialize.enum_to_pattern(map, meta)
    {{:%{}, [], tuples}, guard}
  end
end

pin_or_guard = [
  {Reference, :ref, :is_reference},
  {PID, :pid, :is_pid},
  {Port, :port, :is_port}
]

for {module, var_name, guard} <- pin_or_guard do
  defimpl Mneme.Serializer, for: module do
    def to_pattern(value, meta) do
      case Mneme.Serialize.fetch_pinned(value, meta[:binding]) do
        {:ok, pin} -> {pin, nil}
        :error -> Mneme.Serialize.guard(unquote(var_name), unquote(guard))
      end
    end
  end
end

for module <- [DateTime, NaiveDateTime, Date, Time] do
  defimpl Mneme.Serializer, for: module do
    def to_pattern(value, meta) do
      case Mneme.Serialize.fetch_pinned(value, meta[:binding]) do
        {:ok, pin} -> {pin, nil}
        :error -> {value |> inspect() |> Code.string_to_quoted!(), nil}
      end
    end
  end
end

defimpl Mneme.Serializer, for: Any do
  def to_pattern(%URI{} = uri, meta) do
    struct_to_pattern(URI, Map.delete(uri, :authority), meta)
  end

  def to_pattern(%struct{} = value, meta) do
    struct_to_pattern(struct, value, meta)
  end

  defp struct_to_pattern(struct, map, meta) do
    default = struct.__struct__()
    aliases = struct |> Module.split() |> Enum.map(&String.to_atom/1)

    {tuples, guard} =
      map
      |> Map.to_list()
      |> Enum.filter(fn {k, v} -> v != Map.get(default, k) end)
      |> Mneme.Serialize.enum_to_pattern(meta)

    {{:%, [], [{:__aliases__, [], aliases}, {:%{}, [], tuples}]}, guard}
  end
end
