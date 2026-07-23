defmodule PresidentialBridgeTest do
  use ExUnit.Case
  doctest PresidentialBridge

  test "greets the world" do
    assert PresidentialBridge.hello() == :world
  end
end
