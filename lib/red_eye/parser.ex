defmodule RedEye.Parser do
  @type result :: {:ok, term(), [String.t()]} | {:error, String.t()}
  @type t :: %__MODULE__{
          parse: (list(String.t()) -> result())
        }

  defstruct [:parse]

  @spec parse(t(), [String.t()]) :: result()
  def parse(%__MODULE__{parse: parse}, buffer) when is_function(parse, 1) and is_list(buffer) do
    parse.(buffer)
  end
end
