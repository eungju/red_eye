defmodule RedEye do
  alias RedEye.Parser

  @spec parse(Parser.t(), [String.t()]) :: Parser.result()
  def parse(%Parser{} = parser, args) when is_list(args) do
    Parser.parse(parser, args)
  end
end
