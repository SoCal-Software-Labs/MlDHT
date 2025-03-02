defmodule CrissCrossDHT.Server.Utils.Test do
  use ExUnit.Case

  alias CrissCrossDHT.Server.Utils, as: Utils

  test "IPv4 address with tuple_to_ipstr/2" do
    assert Utils.tuple_to_ipstr({127, 0, 0, 1}, 6881) == "127.0.0.1:6881"
  end

  test "IPv6 address with tuple_to_ipstr/2" do
    ip_str = "[2001:41D0:000C:05AC:0005:0000:0000:0001]:6881"
    assert Utils.tuple_to_ipstr({8193, 16_848, 12, 1452, 5, 0, 0, 1}, 6881) == ip_str
  end
end
