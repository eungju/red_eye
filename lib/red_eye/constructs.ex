defmodule RedEye.Constructs do
  alias RedEye.{Parser, ValueParser}

  @type value_parser :: ValueParser.t()
  @type parser :: Parser.t()

  @doc """
  Creates a parser that combines multiple parsers into a single keyword list parser.
  Each parser in the keyword list is applied to parse different parts of the input,
  and the results are combined into an keyword list with the same structure.

  Each parser is run in order against the remaining input. Values of `nil` and
  `false` are treated as absent and omitted from the returned keyword list,
  which makes optional value parsers and boolean options compose naturally.

      iex> import RedEye.Primitives
      iex> import RedEye.ValueParser
      iex> parser = keyword_list([
      ...>   host: option(["-h", "--host"], string()),
      ...>   port: option(["-p", "--port"], integer())
      ...> ])
      iex> RedEye.parse(parser, ["-h", "localhost", "status"])
      {:ok, [host: "localhost"], ["status"]}
  """
  @spec keyword_list(nonempty_list({atom, parser()})) :: parser()
  def keyword_list(pairs) when is_list(pairs) do
    pairs = validate_keyword_pairs(pairs)
    %Parser{
      parse: fn buffer -> parse_keyword_pairs(pairs, [], buffer) end
    }
  end

  defp validate_keyword_pairs(pairs) do
    Enum.map(pairs, fn
      {key, %Parser{} = parser} when is_atom(key) ->
        {key, parser}

      {key, _parser} ->
        raise ArgumentError, "keyword_list keys must be atoms, got: #{inspect(key)}"

      other ->
        raise ArgumentError,
              "keyword_list entries must be {atom, parser} pairs, got: #{inspect(other)}"
    end)
  end

  defp parse_keyword_pairs([], acc, buffer) do
    {:ok, Enum.reverse(acc), buffer}
  end

  defp parse_keyword_pairs([{key, parser} | rest], acc, buffer) do
    case Parser.parse(parser, buffer) do
      {:ok, value, remaining} ->
        acc = if keyword_value_present?(value), do: [{key, value} | acc], else: acc
        parse_keyword_pairs(rest, acc, remaining)

      {:error, message} ->
        {:error, message}
    end
  end

  defp keyword_value_present?(nil), do: false
  defp keyword_value_present?(false), do: false
  defp keyword_value_present?(_value), do: true
end
