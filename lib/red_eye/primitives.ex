defmodule RedEye.Primitives do
  @moduledoc """
  Primitive parser constructors.

  These parsers are the foundation for higher-level combinators.
  """

  alias RedEye.{Parser, ValueParser}

  @type value_parser :: ValueParser.t()
  @type parser :: Parser.t()

  @doc """
  Builds a parser that always succeeds with `value` and consumes no input.

      iex> RedEye.parse(constant(:add), ["--file", "example.txt"])
      {:ok, :add, ["--file", "example.txt"]}
  """
  @spec constant(term()) :: parser()
  def constant(value) do
    %Parser{parse: fn buffer -> {:ok, value, buffer} end}
  end

  @doc """
  Builds a parser that always fails and consumes no input.

      iex> RedEye.parse(fail(), ["--file", "example.txt"])
      {:error, "No value provided"}
  """
  @spec fail() :: parser()
  def fail() do
    %Parser{
      parse: fn _ -> {:error, "No value provided"} end
    }
  end

  @doc """
  Builds an option parser.

  With no value parser, the option is a Boolean flag: it returns `true` when the
  flag is present and `false` when absent.

      iex> RedEye.parse(option(["-v", "--verbose"]), ["-v"])
      {:ok, true, []}

  Boolean short flags can be bundled, so `-abc` is equivalent to `-a -b -c`.

      iex> RedEye.parse(option(["-b"]), ["-abc", "file"])
      {:ok, true, ["-ac", "file"]}
  """
  @spec option(nonempty_list(String.t())) :: parser()
  def option(names) when is_list(names) do
    aliases =
      names
      |> validate_names()
      |> aliases()

    %Parser{parse: fn buffer -> parse_boolean_option(buffer, aliases) end}
  end

  @doc """
  Builds an option parser with a value parser.

  Passing a value parser makes the option expect a value and return `nil` when
  the option is absent:

      iex> RedEye.parse(option(["-n", "--name"], RedEye.ValueParser.string()), ["-n", "Ada"])
      {:ok, "Ada", []}

  Supported forms include `--port 8080`, `--port=8080`, `-p 8080`, `-p 8080`,
  `/PORT 8080`, and `/PORT:8080`.
  """
  @spec option(nonempty_list(String.t()), value_parser()) :: parser()
  def option(names, %ValueParser{} = value_parser) when is_list(names) do
    aliases =
      names
      |> validate_names()
      |> aliases()

    %Parser{parse: fn buffer -> parse_value_option(buffer, aliases, value_parser) end}
  end

  defp aliases(names) do
    %{
      exact: Enum.uniq(names),
      short_chars: short_alias_chars(names),
      value_delimiters: value_delimiter_aliases(names)
    }
  end

  defp validate_names(names) do
    Enum.map(names, fn
      name when is_binary(name) -> name
      other -> raise ArgumentError, "option names must be strings, got: #{inspect(other)}"
    end)
  end

  defp parse_boolean_option(buffer, aliases) do
    case scan(buffer, aliases, &match_boolean_option/2) do
      {:ok, true, rest} -> {:ok, true, rest}
      {:error, message} -> {:error, message}
      :not_found -> {:ok, false, buffer}
    end
  end

  defp parse_value_option(buffer, aliases, value_parser) do
    case scan(buffer, aliases, &match_value_option/2) do
      {:ok, {:raw, raw_value}, rest} -> parse_raw_value(raw_value, rest, value_parser)
      {:error, message} -> {:error, message}
      :not_found -> {:ok, nil, buffer}
    end
  end

  defp scan(buffer, aliases, matcher) do
    do_scan(buffer, [], aliases, matcher)
  end

  defp do_scan([], _seen, _aliases, _matcher), do: :not_found
  defp do_scan(["--" | _] = _remaining, _seen, _aliases, _matcher), do: :not_found

  defp do_scan([arg | rest], seen, aliases, matcher) do
    case matcher.(arg, aliases) do
      :no_match ->
        do_scan(rest, [arg | seen], aliases, matcher)

      {:consume, value} ->
        {:ok, value, rebuild(seen, rest)}

      :take_next ->
        case rest do
          [] -> {:error, "Missing value"}
          ["--" | _] -> {:error, "Missing value"}
          [raw_value | remaining] -> {:ok, {:raw, raw_value}, rebuild(seen, remaining)}
        end

      {:replace, value, replacement} ->
        {:ok, value, rebuild(seen, [replacement | rest])}

      {:error, message} ->
        {:error, message}
    end
  end

  defp rebuild(seen, rest), do: Enum.reverse(seen) ++ rest

  defp match_boolean_option(arg, %{exact: exact, short_chars: short_chars}) do
    cond do
      arg in exact ->
        {:consume, true}

      boolean_inline_value?(arg, exact) ->
        {:error, "Unexpected value"}

      true ->
        bundled_short_flag(arg, short_chars)
    end
  end

  defp match_value_option(arg, %{exact: exact, value_delimiters: value_delimiters}) do
    cond do
      arg in exact ->
        :take_next

      true ->
        delimited_value(arg, value_delimiters)
    end
  end

  defp parse_raw_value(raw_value, rest, value_parser) do
    case ValueParser.parse(value_parser, raw_value) do
      {:ok, value} -> {:ok, value, rest}
      {:error, message} -> {:error, message}
    end
  rescue
    exception in ArgumentError -> {:error, Exception.message(exception)}
  end

  defp value_delimiter_aliases(names) do
    names
    |> Enum.flat_map(fn
      "--" <> name -> [{"--" <> name, "="}]
      "/" <> _ = name -> [{name, ":"}, {name, "="}]
      name -> [{name, "="}]
    end)
    |> Enum.uniq()
    |> Enum.sort_by(fn {alias, _delimiter} -> -byte_size(alias) end)
  end

  defp delimited_value(arg, aliases) do
    Enum.find_value(aliases, fn {alias, delimiter} ->
      prefix = alias <> delimiter

      if String.starts_with?(arg, prefix) do
        {:consume, {:raw, String.replace_prefix(arg, prefix, "")}}
      end
    end) || :no_match
  end

  defp short_aliases(names) do
    names
    |> Enum.filter(fn
      "-" <> rest -> byte_size(rest) == 1
      _ -> false
    end)
    |> Enum.sort_by(&(-byte_size(&1)))
  end

  defp short_alias_chars(names) do
    names
    |> short_aliases()
    |> Enum.map(fn "-" <> char -> char end)
  end

  defp bundled_short_flag("--" <> _, _chars), do: :no_match

  defp bundled_short_flag("-" <> bundle = arg, chars) when byte_size(arg) > 2 do
    graphemes = String.graphemes(bundle)

    case Enum.find(chars, &(&1 in graphemes)) do
      nil ->
        :no_match

      char ->
        remaining = graphemes |> List.delete(char) |> Enum.join()

        case remaining do
          "" -> {:consume, true}
          _ -> {:replace, true, "-" <> remaining}
        end
    end
  end

  defp bundled_short_flag(_arg, _chars), do: :no_match

  defp boolean_inline_value?(arg, aliases) do
    Enum.any?(aliases, fn alias ->
      String.starts_with?(arg, alias <> "=") or String.starts_with?(arg, alias <> ":")
    end)
  end
end
