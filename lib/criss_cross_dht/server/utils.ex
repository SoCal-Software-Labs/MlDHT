defmodule CrissCrossDHT.Server.Utils do
  @moduledoc false

  @doc ~S"""
  This function gets a tuple as IP address and a port and returns a
  string which contains the IPv4 or IPv6 address and port in the following
  format: "127.0.0.1:6881".

    ## Example
    iex> CrissCrossDHT.Server.Utils.tuple_to_ipstr({127, 0, 0, 1}, 6881)
    "127.0.0.1:6881"
  """
  @aad "AES256GCM"
  @schnorr_context "CrissCross-DHT"

  alias CrissCrossDHT.Server.Storage

  def tuple_to_ipstr({oct1, oct2, oct3, oct4}, port) do
    "#{oct1}.#{oct2}.#{oct3}.#{oct4}:#{port}"
  end

  def tuple_to_ipstr(ipv6_addr, port) when tuple_size(ipv6_addr) == 8 do
    ip_str =
      String.duplicate("~4.16.0B:", 8)
      ## remove last ":" of the string
      |> String.slice(0..-2)
      |> :io_lib.format(Tuple.to_list(ipv6_addr))
      |> List.to_string()

    "[#{ip_str}]:#{port}"
  end

  @doc ~S"""
  This function generates a 256 bit (32 byte) random node id as a
  binary.
  """
  @spec gen_node_id :: Types.node_id()
  def gen_node_id do
    :rand.seed(:exs64, :os.timestamp())

    s =
      Stream.repeatedly(fn -> :rand.uniform(255) end)
      |> Enum.take(40)
      |> :binary.list_to_bin()

    hash(s)
  end

  def gen_cypher do
    :rand.seed(:exs64, :os.timestamp())

    s =
      Stream.repeatedly(fn -> :rand.uniform(255) end)
      |> Enum.take(40)
      |> :binary.list_to_bin()

    hash(s)
  end

  @compile {:inline, hash: 1}
  def hash(s), do: :crypto.hash(:sha3_256, s)

  @doc """
  TODO
  """
  def gen_secret, do: gen_node_id()

  def config(config, :bootstrap_nodes) do
    Map.get(config, :bootstrap_nodes, [])
    |> Enum.map(fn node ->
      host =
        case node do
          %{host: host} when is_binary(host) ->
            host

          _ ->
            raise "Bootstrap configured without host"
        end

      port =
        case node do
          %{port: port} when is_number(port) ->
            port

          _ ->
            raise "Bootstrap configured without port"
        end

      node_id =
        case node do
          %{node_id: node_id} when is_binary(node_id) ->
            decode_human!(node_id)

          _ ->
            raise "Bootstrap configured without node_id"
        end

      {node_id, host, port}
    end)
  end

  def config(config, :clusters) do
    Map.get(config, :clusters, %{})
    |> Enum.map(fn {k, config} ->
      pub_key =
        case config do
          %{public_key: pub} when not is_nil(pub) ->
            {:ok, pub_key} = load_public_key(decode_human!(pub))
            pub_key

          _ ->
            nil
        end

      priv_key =
        case config do
          %{private_key: priv} when not is_nil(priv) ->
            {:ok, priv_key} = load_private_key(decode_human!(priv))
            priv_key

          _ ->
            nil
        end

      cypher =
        case config do
          %{secret: secret} when not is_nil(secret) ->
            decode_human!(secret)

          _ ->
            raise "Cluster #{k} configured without secret"
        end

      {decode_human!(k), %{cypher: cypher, public_key: pub_key, private_key: priv_key}}
    end)
    |> Enum.into(%{})
  end

  def config(config, value, ret \\ nil), do: Map.get(config, value, ret)

  def encrypt(secret, payload) do
    do_encrypt(payload, secret)
  end

  def decrypt(payload, secret) do
    do_decrypt(payload, secret)
  end

  def verify_signature(%{public_key: nil}, value, signature), do: false

  def verify_signature(%{public_key: pub_key}, msg, signature) do
    case ExSchnorr.verify(pub_key, msg, signature, @schnorr_context) do
      {:ok, true} ->
        true

      e ->
        false
    end
  end

  def sign(msg, priv_key) do
    ExSchnorr.sign(priv_key, msg, @schnorr_context)
  end

  defp do_encrypt(val, key) do
    iv = :crypto.strong_rand_bytes(32)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, to_string(val), @aad, true)

    iv <> tag <> ciphertext
  end

  defp do_decrypt(ciphertext, key) do
    <<iv::binary-32, tag::binary-16, ciphertext::binary>> = ciphertext
    :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false)
  end

  def wrap(header, body) do
    ["0A", header, body]
  end

  def unwrap("0A" <> <<cluster_header::binary-size(32), body::binary>>) do
    {cluster_header, body}
  end

  def encode_human(bin) do
    Base58.encode(bin)
  end

  def decode_human!(bin) do
    Base58.decode(bin)
  end

  def combine_to_sign(list) do
    list
    |> Enum.map(&to_string(&1))
    |> Enum.join(".")
  end

  def name_from_private_rsa_key(priv_key) do
    {:ok, pub_key} = ExSchnorr.public_from_private(priv_key)
    {:ok, encoded} = ExSchnorr.public_to_bytes(pub_key)
    hash(hash(encoded))
  end

  def check_generation(storage_mod, storage_pid, cluster, name, generation) do
    case storage_mod.get_name(storage_pid, cluster, name) do
      {value, saved_gen} -> saved_gen < generation
      _ -> true
    end
  end

  def load_public_key(s) do
    ExSchnorr.public_from_bytes(s)
  end

  def load_private_key(s) do
    ExSchnorr.private_from_bytes(s)
  end
end
