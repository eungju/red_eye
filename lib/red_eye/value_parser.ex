defmodule RedEye.ValueParser do
  @moduledoc """
  Value parsers for option arguments.
  """

  @type result :: {:ok, term()} | {:error, String.t()}
  @type t :: %__MODULE__{
          metavar: String.t(),
          parse: (String.t() -> result())
        }

  defstruct [:metavar, :parse]

  @spec parse(t(), String.t()) :: result()
  def parse(%__MODULE__{parse: parse}, input)
      when is_function(parse, 1) and is_bitstring(input) do
    parse.(input)
  end

  @type common_option :: {:metavar, String.t()}

  @type string_option :: common_option() | {:pattern, Regex.t()}

  @doc """
  Create a ValueParser for strings.

  This parser validates that the input is a string and optionally checks
  if it matches a specified regular expression pattern.

  Accepts any string as valid input:
      iex> parse(string(), "hello")
      {:ok, "hello"}

  Accepts strings that match the specified pattern:
      iex> parse(string(pattern: ~r/^[a-z]+$/), "hello")
      {:ok, "hello"}

  Rejects strings that do not match the specified pattern:
      iex> parse(string(pattern: ~r/^[a-z]+$/), "hello123")
      {:error, "Expected a string matching pattern ~r/^[a-z]+$/, but got \\"hello123\\""}
  """
  @spec string(list(string_option)) :: t()
  def string(opts \\ []) do
    metavar = Keyword.get(opts, :metavar, "STRING")
    pattern = Keyword.get(opts, :pattern)

    %__MODULE__{
      metavar: metavar,
      parse: fn input ->
        if pattern && !Regex.match?(pattern, input) do
          {:error,
           "Expected a string matching pattern #{inspect(pattern)}, but got #{inspect(input)}"}
        else
          {:ok, input}
        end
      end
    }
  end

  @type integer_option :: common_option() | {:min, integer()} | {:max, integer()}

  @doc """
  Creates a ValueParser for integers.

  This parser validates that the input is a valid integer number
  and optionally enforces minimum and maximum value constraints.

  Accepts valid integers:
      iex> parse(integer(), "42")
      {:ok, 42}

  Rejects invalid integers:
      iex> parse(integer(), "fortytwo")
      {:error, "Expected a valid integer, but got \\"fortytwo\\""}

  Rejects integers outside the specified range:
      iex> parser = integer(min: 1, max: 100)
      iex> parse(parser, "0")
      {:error, "Expected a value greater than or equal to 1, but got 0"}
      iex> parse(parser, "101")
      {:error, "Expected a value less than or equal to 100, but got 101"}
  """
  @spec integer(list(integer_option)) :: t()
  def integer(opts \\ []) do
    metavar = Keyword.get(opts, :metavar, "INTEGER")

    %__MODULE__{
      metavar: metavar,
      parse: fn input ->
        case Integer.parse(input) do
          {integer, ""} ->
            min = Keyword.get(opts, :min)
            max = Keyword.get(opts, :max)

            cond do
              min != nil and integer < min ->
                {:error, "Expected a value greater than or equal to #{min}, but got #{integer}"}

              max != nil and integer > max ->
                {:error, "Expected a value less than or equal to #{max}, but got #{integer}"}

              true ->
                {:ok, integer}
            end

          _ ->
            {:error, "Expected a valid integer, but got #{inspect(input)}"}
        end
      end
    }
  end

  @type float_option :: common_option() | {:min, float()} | {:max, float()}

  @doc """
  Creates a ValueParser for floating-point numbers.

  This parser validates that the input is a valid floating-point number
  and optionally enforces minimum and maximum value constraints.

  Accepts valid floating-point numbers:
      iex> parse(float(), "3.14")
      {:ok, 3.14}

  Rejects invalid floating-point numbers:
      iex> parse(float(), "pi")
      {:error, "Expected a valid floating-point number, but got \\"pi\\""}

  Rejects numbers outside the specified range:
      iex> parser = float(min: 1.0, max: 10.0)
      iex> parse(parser, "0.9")
      {:error, "Expected a value greater than or equal to 1.0, but got 0.9"}
      iex> parse(parser, "10.1")
      {:error, "Expected a value less than or equal to 10.0, but got 10.1"}
  """
  @spec float(list(float_option)) :: t()
  def float(opts \\ []) do
    metavar = Keyword.get(opts, :metavar, "NUMBER")

    %__MODULE__{
      metavar: metavar,
      parse: fn input ->
        case Float.parse(input) do
          {float, ""} ->
            min = Keyword.get(opts, :min)
            max = Keyword.get(opts, :max)

            cond do
              min != nil and float < min ->
                {:error, "Expected a value greater than or equal to #{min}, but got #{float}"}

              max != nil and float > max ->
                {:error, "Expected a value less than or equal to #{max}, but got #{float}"}

              true ->
                {:ok, float}
            end

          _ ->
            {:error, "Expected a valid floating-point number, but got #{inspect(input)}"}
        end
      end
    }
  end

  @type choice_option :: common_option()

  @doc """
  Creates a ValueParser that accepts one of multiple values.

  The `choices` can be a non-empty list of strings:
      iex> parser = choice(["info", "warn", "error"])
      iex> parse(parser, "info")
      {:ok, "info"}
      iex> parse(parser, "alert")
      {:error, "Expected one of [\\"info\\", \\"warn\\", \\"error\\"], but got \\"alert\\""}

  Or a non-empty list of numbers:
      iex> parser = choice([1024, 2048, 4096])
      iex> parse(parser, "4096")
      {:ok, 4096}
      iex> parse(parser, "512")
      {:error, "Expected one of [1024, 2048, 4096], but got 512"}

  The `choices` should not be empty:
      iex> choice([])
      ** (ArgumentError) Expected at least one choice, but got an empty list.

  The `choices` should be of the same type:
      iex> choice(["small", "medium", 3])
      ** (ArgumentError) Expected every choice to be a string, but got 3.

      iex> choice([1024, "large"])
      ** (ArgumentError) Expected every choice to be a number, but got \"large\".

  The `choices` should not contain empty strings:
      iex> choice(["", "valid"])
      ** (ArgumentError) Empty strings are not allowed as choices.
  """
  @spec choice(nonempty_list(String.t()) | nonempty_list(number()), list(choice_option())) :: t()
  def choice(choices, opts \\ []) do
    unless Enum.any?(choices) do
      raise ArgumentError, "Expected at least one choice, but got an empty list."
    end

    number_type = choices |> List.first() |> is_number()

    choices
    |> Enum.each(fn choice ->
      if is_number(choice) != number_type do
        raise ArgumentError,
              "Expected every choice to be a #{if(number_type, do: "number", else: "string")}, but got #{inspect(choice)}."
      end

      if choice == "" do
        raise ArgumentError, "Empty strings are not allowed as choices."
      end
    end)

    metavar = Keyword.get(opts, :metavar, "TYPE")

    %__MODULE__{
      metavar: metavar,
      parse: fn input ->
        input =
          if number_type do
            case Integer.parse(input) do
              {integer, ""} ->
                integer

              _ ->
                case Float.parse(input) do
                  {float, ""} -> float
                  _ -> input
                end
            end
          else
            input
          end

        if Enum.any?(choices, &(&1 == input)) do
          {:ok, input}
        else
          {:error, "Expected one of #{inspect(choices)}, but got #{inspect(input)}"}
        end
      end
    }
  end
end
