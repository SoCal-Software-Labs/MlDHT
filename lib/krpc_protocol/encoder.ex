defmodule KRPCProtocol.Encoder do
  @moduledoc ~S"""
  KRPCProtocol.Encoder provides functions to encode mainline DHT messages.
  """

  @typedoc """
  A node_id is a bitstring with a size of 160 bit which uniquely identifies every node.
  """
  @type node_id :: <<_::256>>

  @typedoc """
  A target also belongs to the same node_id space and is a bitstring with a size of 160 bit.
  """
  @type target :: <<_::256>>

  @typedoc """
  A transaction ID (t_id) is a bitstring with a size of 16 bit which correlates
  multiple queries to the same node.
  """
  @type t_id :: <<_::16>>

  @doc ~S"""
  This function returns a bencoded Mainline DHT message.

  ## error

  When the first argument is `:error`, the function encodes an error message.

  ### Example

      iex> KRPCProtocol.encode(:error, code: 202, msg: "Server Error", tid: "aa")
      "d1:eli202e12:Server Errore1:t2:aa1:y1:ee"

  ## ping

  The purpose of a ping query is check if another node is available. When the
  first argument is `:ping`, the function encodes a ping message. The function
  needs the `node_id` and a `t_id`.

  ### Example

      iex> KRPCProtocol.encode(:ping, tid: "aa", node_id: "bb")
      "d1:ad2:id2:bbe1:q4:ping1:t2:aa1:y1:qe"

  ## find_node query

  A find_node query is used to find more nodes for a given target. When the
  first argument is `:find_node`, the function encodes a find_node message. The
  following arguments are required: transaction id, node id and a target. The
  'want' argument is optional and can be set to "n6" if you are only intrested
  in nodes that can provide an IPv6 address.

  ### Examples

      iex> KRPCProtocol.encode(:find_node, tid: "aa", node_id: "bb", target: "cc")
      "d1:ad2:id2:bb6:target2:cc4:want2:n4e1:q9:find_node1:t2:aa1:y1:qe"

      iex> KRPCProtocol.encode(:find_node, tid: "aa", node_id: "bb", target: "cc", want: "n6")
      "d1:ad2:id2:bb6:target2:cc4:want2:n6e1:q9:find_node1:t2:aa1:y1:qe"

  ## get_peers query

  A get_peers query is used to find nodes associated with a info_hash. When the
  first argument is `:get_peers`, the function encodes a get_peers message. The
  required arguments are node_id and info_hash. The optional arguments are
  `scrape`, `noseed`, and `want`. Please take a look at
  [BEP0005](http://www.bittorrent.org/beps/bep_0005.html) and
  [BEP0033](http://www.bittorrent.org/beps/bep_0033.html) for more information
  about these arguments.

  ### Examples

      iex> KRPCProtocol.encode(:get_peers, node_id: "aa", info_hash: "bb" , tid: "cc")
      "d1:ad2:id2:aa9:info_hash2:bbe1:q9:get_peers1:t2:cc1:y1:qe"

      iex> KRPCProtocol.encode(:get_peers, node_id: "aa", info_hash: "bb" , tid: "cc", scrape: true)
      "d1:ad2:id2:aa9:info_hash2:bb6:scrapei1ee1:q9:get_peers1:t2:cc1:y1:qe"

  ## announce_peer

  With the announce_peer message, a peer announces that it is downloading a
  torrent on a specific port. When the first argument is `:announce_peer`, the
  function encodes a announce_peer message. Required arguments are nod_id,
  info_hash and tid. Optional arguments are port, implied_port and token.

  ### Examples

      iex> KRPCProtocol.encode(:announce_peer, node_id: "aa", info_hash: "bb", tid: "dd", port: 2342)
      "d1:ad2:id2:aa9:info_hash2:bb4:porti2342ee1:q13:announce_peer1:t2:dd1:y1:qe"

      iex> KRPCProtocol.encode(:announce_peer, node_id: "aa", info_hash: "bb", tid: "dd", implied_port: true)
      "d1:ad2:id2:aa12:implied_porti1e9:info_hash2:bbe1:q13:announce_peer1:t2:dd1:y1:qe"

  ## ping reply

  The answer to a ping message is a ping reply message.

  ### Example

      iex> KRPCProtocol.encode(:ping_reply, tid: "aa", node_id: "bb")
      "d1:rd2:id2:bbe1:t2:aa1:y1:re"

  ## find_node reply

  A find_node reply contains contact information for the requested target. The
  contact information must be a list which contains node information in the
  following tuple: `{"nodeid", {97, 98, 99, 100}, 9797}`. This works also for
  IPv6 addresses.

  ### Example

      iex> KRPCProtocol.encode(:find_node_reply, node_id: "bb", nodes: [{"nodeid", {97, 98, 99, 100}, 9797}], tid: "aa")
      "d1:rd2:id2:bb5:nodes12:nodeidabcd&Ee1:t2:aa1:y1:re"

  ## get_peers reply

  A get_peers reply contains contact information for a get_peers request. The
  contact information must be a list which contains node information in the
  following tuple: `{{97, 98, 99, 100}, 9797}`. This works also for IPv6
  addresses.

  ### Example

       iex>KRPCProtocol.encode(:get_peers_reply, node_id: "bb", values: [{{97, 98, 99, 100}, 9797}], tid: "aa", token: "b")
       "d1:rd2:id2:bb5:token1:b6:values6:abcd&Ee1:t2:aa1:y1:re"

  """

  #########
  # Error #
  #########

  def encode(:error, code: code, msg: msg, tid: tid) do
    do_encode(%{:y => :e, :t => tid, :e => [code, msg]})
  end

  ###########
  # Queries #
  ###########

  def encode(:ping, tid: tid, node_id: node_id) do
    gen_dht_query(:ping, tid, %{:id => node_id})
  end

  def encode(:ping, node_id: node_id) do
    encode(:ping, tid: gen_tid(), node_id: node_id)
  end

  def encode(:find_node, node_id: id, target: target) do
    encode(:find_node, tid: gen_tid(), node_id: id, target: target, want: "n4")
  end

  def encode(:find_node, node_id: id, target: target, want: want) do
    encode(:find_node, tid: gen_tid(), node_id: id, target: target, want: want)
  end

  def encode(:find_node, tid: tid, node_id: id, target: target) do
    encode(:find_node, tid: tid, node_id: id, target: target, want: "n4")
  end

  def encode(:find_node, tid: tid, node_id: id, target: target, want: want) do
    gen_dht_query(:find_node, tid, %{:id => id, :target => target, :want => want})
  end

  def encode(:store, tid: tid, node_id: id, key: key, value: value, ttl: ttl, signature: sig) do
    gen_dht_query(:store, tid, %{
      :id => id,
      :key => key,
      :value => value,
      :ttl => ttl,
      :sig => sig
    })
  end

  def encode(:store_name,
        tid: tid,
        node_id: id,
        name: name,
        value: value,
        ttl: ttl,
        key_string: key_string,
        generation: generation,
        signature: sig,
        signature_ns: sig_ns
      ) do
    gen_dht_query(:store_name, tid, %{
      :id => id,
      :name => name,
      :value => value,
      :ttl => ttl,
      :priv => key_string,
      :gen => generation,
      :sig => sig,
      :sig_ns => sig_ns
    })
  end

  def encode(:find_value, tid: tid, node_id: id, key: key) do
    gen_dht_query(:find_value, tid, %{:id => id, :key => key})
  end

  def encode(:find_name, tid: tid, node_id: id, name: name, generation: generation) do
    gen_dht_query(:find_name, tid, %{:id => id, :name => name, :gen => generation})
  end

  def encode(:get_peers, args) do
    options =
      args[:node_id]
      |> query_dict(args[:info_hash])
      |> add_option_if_defined(:scrape, args[:scrape])
      |> add_option_if_defined(:noseed, args[:noseed])
      |> add_option_if_defined(:want, args[:want])

    gen_dht_query(:get_peers, args[:tid] || gen_tid(), options)
  end

  def encode(:announce_peer, args) do
    options =
      args[:node_id]
      |> query_dict(args[:info_hash])
      |> add_option_if_defined(:port, args[:port])
      |> add_option_if_defined(:meta, args[:meta])
      |> add_option_if_defined(:token, args[:token])
      |> add_option_if_defined(:ttl, args[:ttl])

    gen_dht_query(:announce_peer, args[:tid] || gen_tid(), options)
  end

  ###########
  # Replies #
  ###########

  def encode(:ping_reply, tid: tid, node_id: node_id) do
    gen_dht_response(%{:id => node_id}, tid)
  end

  def encode(:store_name_reply, tid: tid, node_id: node_id, name: name, wrote: wrote) do
    gen_dht_response(%{:id => node_id, :name => name, :wrote => wrote}, tid)
  end

  def encode(:store_reply, tid: tid, node_id: node_id, key: key, wrote: wrote) do
    gen_dht_response(%{:id => node_id, :key => key, :wrote => wrote}, tid)
  end

  def encode(:find_name_reply,
        tid: tid,
        node_id: node_id,
        name: name,
        value: value,
        generation: generation,
        signature_cluster: signature_cluster,
        signature_name: signature_name,
        key_string: key_string,
        ttl: ttl,
        token: token
      ) do
    gen_dht_response(
      %{
        :id => node_id,
        :name => name,
        :value => value,
        :gen => generation,
        :sig => signature_cluster,
        :sig_n => signature_name,
        :priv => key_string,
        :token => token,
        :ttl => ttl
      },
      tid
    )
  end

  def encode(:find_name_nodes_reply, node_id: id, name: name, nodes: nodes, tid: tid, token: token) do
    gen_dht_response(%{:id => id, :name => name, :nodes => nodes, :token => token}, tid)
  end

  def encode(:find_name_nodes_reply,
        node_id: id,
        name: name,
        nodes6: nodes,
        tid: tid,
        token: token
      ) do
    gen_dht_response(%{:id => id, :name => name, :nodes => nodes, :token => token}, tid)
  end

  def encode(:find_value_reply, tid: tid, node_id: node_id, key: key, value: value, token: token) do
    gen_dht_response(%{:id => node_id, :key => key, :value => value, :token => token}, tid)
  end

  def encode(:find_value_nodes_reply, node_id: id, key: key, nodes: nodes, tid: tid, token: token) do
    gen_dht_response(%{:id => id, :key => key, :nodes => nodes, :token => token}, tid)
  end

  def encode(:find_value_nodes_reply, node_id: id, key: key, nodes6: nodes, tid: tid, token: token) do
    gen_dht_response(%{:id => id, :key => key, :nodes6 => nodes, :token => token}, tid)
  end

  def encode(:find_node_reply, node_id: id, nodes: nodes, tid: tid) do
    gen_dht_response(%{:id => id, :nodes => nodes}, tid)
  end

  def encode(:find_node_reply, node_id: id, nodes6: nodes, tid: tid) do
    gen_dht_response(%{:id => id, :nodes6 => nodes}, tid)
  end

  def encode(:get_peers_reply,
        node_id: id,
        info_hash: info_hash,
        nodes: nodes,
        tid: tid,
        token: token
      ) do
    gen_dht_response(
      %{
        :id => id,
        :token => token,
        :nodes => nodes,
        :info_hash => info_hash
      },
      tid
    )
  end

  def encode(:get_peers_reply,
        node_id: id,
        info_hash: info_hash,
        values: values,
        tid: tid,
        token: token
      ) do
    gen_dht_response(
      %{
        :id => id,
        :token => token,
        :values => values,
        :info_hash => info_hash
      },
      tid
    )
  end

  @doc ~S"""
  This function generates a 16 bit (2 byte) random transaction ID and converts
  it to a binary and returns it. This transaction ID is echoed in the response.
  """
  @spec gen_tid() :: t_id
  def gen_tid do
    <<System.monotonic_time()::big-integer-64>>
  end

  #####################
  # Private Functions #
  #####################

  defp gen_dht_query(command, tid, options) when is_map(options) do
    do_encode(%{:y => :q, :t => tid, :q => command, :a => options})
  end

  defp gen_dht_response(options, tid) when is_map(options) do
    do_encode(%{:y => :r, :t => tid, :r => options})
  end

  # IPv4 address
  def node_to_binary({oct1, oct2, oct3, oct4}, port) do
    <<oct1::8, oct2::8, oct3::8, oct4::8, port::16>>
  end

  # IPv6 address
  def node_to_binary(ip, port) when tuple_size(ip) == 8 do
    ipstr =
      ip
      |> Tuple.to_list()
      |> Enum.map(&(<<_oct1::8, _oct2::8>> = <<&1::16>>))
      |> Enum.reduce(fn x, y -> y <> x end)

    <<ipstr::binary, port::16>>
  end

  # This function returns a bencoded mainline DHT get_peers query. It
  # needs a 20 bytes node ID and a 20 bytes info_hash as an
  # argument. Optional arguments are [want: "n6", scrape: true]
  defp add_option_if_defined(dict, _key, nil), do: dict
  defp add_option_if_defined(dict, key, true), do: Map.put_new(dict, key, 1)

  defp add_option_if_defined(dict, key, value) do
    Map.put_new(dict, key, value)
  end

  defp query_dict(id, info_hash) do
    %{:id => id, :hash => info_hash}
  end

  defp do_encode(obj) do
    # Bencodex.encode
    :erlang.term_to_binary(obj)
  end
end
