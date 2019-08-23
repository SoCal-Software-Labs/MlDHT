defmodule MlDHT.Test do
  use ExUnit.Case

  test "if node_id() returns a String that has a length of 20 characters" do
    node_id = MlDHT.node_id()
    assert byte_size(node_id) == 20
  end

  test "if node_id_enc() returns a String that has a length of 40 characters" do
    node_id_enc = MlDHT.node_id_enc()
    assert String.length(node_id_enc) == 40
  end

  test "if MlDHT.search" do
    Process.register self(), :mldht_test_search

    ## Wait 3 seconds to ensure that the bootstrapping process has collected
    ## enough nodes
    :timer.sleep(3000)

    "D540FC48EB12F2833163EED6421D449DD8F1CE1F"
    |> Base.decode16!
    |> MlDHT.search(fn (_node) ->
      send :mldht_test_search, {:called_back, :pong}
    end)

    assert_receive {:called_back, :pong}, 40_000
  end

end
