defmodule RedEye.PrimitivesTest do
  use ExUnit.Case, async: true

  doctest RedEye.Primitives, import: true

  import RedEye.Primitives
  import RedEye.ValueParser

  test "option without value returns false when absent" do
    assert RedEye.parse(option(["-v", "--verbose"]), ["input.txt"]) ==
             {:ok, false, ["input.txt"]}
  end

  test "option without value rejects inline values" do
    assert {:error, "Unexpected value"} =
             RedEye.parse(option(["--verbose"]), ["--verbose=true"])
  end

  test "option without value consumes long and short aliases" do
    assert RedEye.parse(option(["-v", "--verbose"]), ["input.txt", "--verbose"]) ==
             {:ok, true, ["input.txt"]}

    assert RedEye.parse(option(["-v", "--verbose"]), ["-v", "input.txt"]) ==
             {:ok, true, ["input.txt"]}
  end

  test "option without value consumes DOS-style names" do
    assert RedEye.parse(option(["/VERBOSE"]), ["input.txt", "/VERBOSE"]) ==
             {:ok, true, ["input.txt"]}
  end

  test "option without value consumes Java-style names" do
    assert RedEye.parse(option(["-verbose"]), ["input.txt", "-verbose"]) ==
             {:ok, true, ["input.txt"]}
  end

  test "option scanning stops at double dash" do
    assert RedEye.parse(option(["--verbose"]), ["--", "--verbose"]) ==
             {:ok, false, ["--", "--verbose"]}
  end

    test "option with value returns nil when absent" do
    assert RedEye.parse(option(["-p", "--port"], integer()), [
             "--host",
             "localhost"
           ]) ==
             {:ok, nil, ["--host", "localhost"]}
  end

  test "option with value returns an error and preserves input when value parsing fails" do
    assert RedEye.parse(option(["-p", "--port"], integer()), [
             "--port",
             "abc"
           ]) ==
             {:error, "Expected a valid integer, but got \"abc\""}
  end

  test "option with value consumes space separated values" do
    assert RedEye.parse(option(["-p", "--port"], integer()), [
             "--port",
             "8080"
           ]) ==
             {:ok, 8080, []}
  end

  test "option with value consumes equals separated values" do
    assert RedEye.parse(option(["-p", "--port"], integer()), [
             "--port=8080"
           ]) ==
             {:ok, 8080, []}
  end

  test "option with value consumes short space separated values" do
    assert RedEye.parse(option(["-p", "--port"], integer()), [
             "-p",
             "8080"
           ]) ==
             {:ok, 8080, []}
  end

  test "option with value consumes short equals separated values" do
    assert RedEye.parse(option(["-p", "--port"], integer()), [
             "-p=8080"
           ]) ==
             {:ok, 8080, []}
  end

  test "option with value consumes DOS-style names with colon separated values" do
    assert RedEye.parse(option(["/PORT"], integer()), ["/PORT:8080"]) ==
             {:ok, 8080, []}
  end

  test "option with value consumes DOS-style names with space separated values" do
    assert RedEye.parse(option(["/PORT"], integer()), ["/PORT", "8080"]) ==
             {:ok, 8080, []}
  end

end
