# MLDHT - Mainline DHT

MLDHT is an [elixir](http://elixir-lang.org/) package that provides a mainline DHT implementation according to [BEP 05](http://www.bittorrent.org/beps/bep_0005.html). It is build on three applications:

  * `DHTServer` - main interface, receives all incoming messages;
  * `KRPCProtocol` - contains modules to encode and decode KRPC messages;
  * `RoutingTable` - maintains contact information of close nodes;

## Example

The first thing we need to do, after the module is loaded, is to bootstrap. This process starts a `find_node` search for a node that belongs to the same bucket as our own node id. In `config.ex` you will find the boostrapping nodes that will be used for that first search. By doing this, we will quickly collect nodes that are close to us.

```elixir
iex> DHTServer.Worker.bootstrap
```

If you are curious and would like to see the content of the `RoutingTable` you can use the following command:

```elixir
iex> RoutingTable.Worker.print
```

To find nodes for a specific infohash, you can use the following function.

```elixir
iex> infohash = "3f19b149f53a50e14fc0b79926a391896eabab6f" |> Hexate.decode ## Ubuntu 15.04
iex> DHTServer.Worker.search(infohash, 6881, fn(node) -> IO.puts "#{inspect node}" end)
```

## Installation

TODO

## License

MLDHT source code is released under MIT License.
Check LICENSE file for more information.