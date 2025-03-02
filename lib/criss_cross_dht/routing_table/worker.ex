defmodule CrissCrossDHT.RoutingTable.Worker do
  @moduledoc false

  use GenServer

  require Logger
  require Bitwise

  alias CrissCrossDHT.Server.Utils
  alias CrissCrossDHT.RoutingTable.Node
  alias CrissCrossDHT.RoutingTable.Bucket
  alias CrissCrossDHT.RoutingTable.Distance

  alias CrissCrossDHT.Search.Worker, as: Search

  #############
  # Constants #
  #############

  ## One minute in mi
  @min_in_ms 60 * 1000

  ## 5 Minutes
  @review_time 5 * @min_in_ms

  ## 5 minutes
  @response_time 15 * @min_in_ms

  ## 5 minutes
  @neighbourhood_maintenance_time 5 * @min_in_ms

  ## 3 minutes
  @bucket_maintenance_time 3 * @min_in_ms

  ## 15 minutes
  @bucket_max_idle_time 15 * @min_in_ms

  ##############
  # Public API #
  ##############

  def start_link(opts) do
    Logger.debug("Starting RoutingTable worker: #{inspect(opts)}")

    init_args = [
      node_id: :crypto.hash(:blake2s, opts[:node_id]),
      node_id_enc: opts[:node_id_enc],
      original_node_id: opts[:node_id],
      ip_tuple: opts[:ip_tuple],
      cluster: opts[:cluster],
      cluster_secret: opts[:cluster_secret],
      rt_name: opts[:rt_name]
    ]

    GenServer.start_link(__MODULE__, init_args, opts)
  end

  def add(name, remote_node_id, address, socket) do
    GenServer.cast(name, {:add, remote_node_id, address, socket})
  end

  def size(name) do
    GenServer.call(name, :size)
  end

  def cache_size(name) do
    GenServer.call(name, :cache_size)
  end

  def update_bucket(name, bucket_index) do
    GenServer.cast(name, {:update_bucket, bucket_index})
  end

  def print(name) do
    GenServer.cast(name, :print)
  end

  def get(name, node_id) do
    node_id = Utils.simple_hash(node_id)
    GenServer.call(name, {:get, node_id})
  end

  def get_by_ip(name, ip_tuple) do
    GenServer.call(name, {:get_by_ip, ip_tuple})
  end

  def closest_nodes(name, target, remote_node_id) do
    target = Utils.simple_hash(target)
    remote_node_id = Utils.simple_hash(remote_node_id)
    GenServer.call(name, {:closest_nodes, target, remote_node_id})
  end

  def closest_nodes(nil, _target), do: []

  def closest_nodes(name, target) do
    target = Utils.simple_hash(target)
    GenServer.call(name, {:closest_nodes, target, nil})
  end

  def del(name, node_id) do
    node_id = Utils.simple_hash(node_id)
    GenServer.call(name, {:del, node_id})
  end

  #################
  # GenServer API #
  #################

  def init(
        node_id: node_id,
        node_id_enc: node_id_enc,
        original_node_id: original_node_id,
        ip_tuple: ip_tuple,
        cluster: cluster,
        cluster_secret: cluster_secret,
        rt_name: rt_name
      ) do
    ## Start timer for peer review
    Process.send_after(self(), :review, @review_time)

    ## Start timer for neighbourhood maintenance
    Process.send_after(
      self(),
      :neighbourhood_maintenance,
      @neighbourhood_maintenance_time + :rand.uniform(@neighbourhood_maintenance_time)
    )

    ## Start timer for bucket maintenance
    Process.send_after(
      self(),
      :bucket_maintenance,
      @bucket_maintenance_time + :rand.uniform(@bucket_maintenance_time)
    )

    ## Generate name of the ets cache table from the node_id as an atom
    ets_name = node_id |> Utils.encode_human() |> String.to_atom()
    ets_name_ip = ("cache" <> node_id) |> Utils.encode_human() |> String.to_atom()

    {:ok,
     %{
       node_id: node_id,
       original_node_id: original_node_id,
       node_id_enc: node_id_enc,
       rt_name: rt_name,
       buckets: [Bucket.new(0)],
       cache: :ets.new(ets_name, [:set, :protected]),
       cache_ip: :ets.new(ets_name_ip, [:set, :protected]),
       cluster: cluster,
       cluster_secret: cluster_secret,
       ip_tuple: ip_tuple
     }}
  end

  @doc """
  This function gets called by an external timer. This function checks when was
  the last time a node has responded to our requests.
  """
  def handle_info(:review, state) do
    new_buckets =
      Enum.map(state.buckets, fn bucket ->
        Bucket.filter(bucket, fn pid ->
          Node.last_time_responded(pid)
          |> evaluate_node(state.cache, state.cache_ip, state.cluster, state.cluster_secret, pid)
        end)
      end)

    ## Restart the Timer
    Process.send_after(self(), :review, @review_time)

    {:noreply, %{state | :buckets => new_buckets}}
  end

  @doc """
  This functions gets called by an external timer. This function takes a random
  node from a random bucket and runs a find_node query with our own node_id as a
  target. By that way, we try to find more and more nodes that are in our
  neighbourhood.
  """
  def handle_info(:neighbourhood_maintenance, state) do
    Distance.gen_node_id(256, state.node_id)
    |> find_node_on_random_node(state)

    ## Restart the Timer
    Process.send_after(
      self(),
      :neighbourhood_maintenance,
      @neighbourhood_maintenance_time + :rand.uniform(@neighbourhood_maintenance_time)
    )

    {:noreply, state}
  end

  @doc """
  This function gets called by an external timer. It iterates through all
  buckets and checks if a bucket has less than 6 nodes and was not updated
  during the last 15 minutes. If this is the case, then we will pick a random
  node and start a find_node query with a random_node from that bucket.

  Excerpt from BEP 0005: "Buckets that have not been changed in 15 minutes
  should be "refreshed." This is done by picking a random ID in the range of the
  bucket and performing a find_nodes search on it."
  """
  def handle_info(:bucket_maintenance, state) do
    state.buckets
    |> Stream.with_index()
    |> Enum.each(fn {bucket, index} ->
      if Bucket.age(bucket) >= @bucket_max_idle_time or Bucket.size(bucket) < 6 do
        Logger.info(
          "Staring find_node search on bucket #{index} for cluster #{Utils.encode_human(state.cluster)}"
        )

        Distance.gen_node_id(index, state.node_id)
        |> find_node_on_random_node(state)
      end
    end)

    Process.send_after(
      self(),
      :bucket_maintenance,
      @bucket_maintenance_time + :rand.uniform(@bucket_maintenance_time)
    )

    {:noreply, state}
  end

  @doc """
  This function returns the 8 closest nodes in our routing table to a specific
  target.
  """
  def handle_call({:closest_nodes, target, remote_node_id}, _from, state) do
    list =
      state.cache
      |> :ets.tab2list()
      |> Enum.filter(&(elem(&1, 0) != remote_node_id))
      |> Enum.sort(fn x, y ->
        Distance.xor_cmp(elem(x, 0), elem(y, 0), target, &(&1 < &2))
      end)
      |> Enum.map(fn x -> elem(elem(x, 1), 0) end)
      |> Enum.slice(0..7)

    {:reply, list, state}
  end

  def handle_call({:get_by_ip, ip_tuple}, _from, state) do
    {:reply, get_node_ip(state.cache_ip, ip_tuple), state}
  end

  @doc """
  This functio returns the pid for a specific node id. If the node
  does not exists, it will try to add it to our routing table. Again, if this
  was successful, this function returns the pid, otherwise nil.
  """
  def handle_call({:get, node_id}, _from, state) do
    {:reply, get_node(state.cache, node_id), state}
  end

  @doc """
  This function returns the number of nodes in our routing table as an integer.
  """
  def handle_call(:size, _from, state) do
    size =
      state.buckets
      |> Enum.map(fn b -> Bucket.size(b) end)
      |> Enum.reduce(fn x, acc -> x + acc end)

    {:reply, size, state}
  end

  @doc """
  This function returns the number of nodes from the cache as an integer.
  """
  def handle_call(:cache_size, _from, state) do
    {:reply, :ets.tab2list(state.cache) |> Enum.count(), state}
  end

  @doc """
  Without parameters this function returns our own node id. If this function
  gets a string as a parameter, it will set this as our node id.
  """
  def handle_call(:node_id, _from, state) do
    {:reply, state.node_id, state}
  end

  def handle_call({:node_id, node_id}, _from, state) do
    ## Generate new name of the ets cache table and rename it
    ets_name = node_id |> Utils.encode_human() |> String.to_atom()
    new_cache = :ets.rename(state.cache, ets_name)

    {:reply, :ok, %{state | :node_id => node_id, :cache => new_cache}}
  end

  @doc """
  This function deletes a node according to its node id.
  """
  def handle_call({:del, node_id}, _from, state) do
    new_bucket = del_node(state.cache, state.cache_ip, state.buckets, node_id)
    {:reply, :ok, %{state | :buckets => new_bucket}}
  end

  @doc """
  This function update the last_update time value in the bucket.
  """
  def handle_cast({:update_bucket, bucket_index}, state) do
    new_bucket =
      state.buckets
      |> Enum.at(bucket_index)
      |> Bucket.update()

    new_buckets =
      state.buckets
      |> List.replace_at(bucket_index, new_bucket)

    {:noreply, %{state | :buckets => new_buckets}}
  end

  @doc """
  This function tries to add a new node to our routing table. It does not add
  the node to the routing table if the node is already in the routing table or
  if the node_id is equal to our own node_id. In this case the function will
  return nil. Otherwise, we will add it to our routing table and return the node
  pid.
  """
  def handle_cast({:add, node_id, address, socket}, state) do
    cond do
      # This is our own node id
      node_id == state.node_id ->
        {:noreply, state}

      # We have this node already in our table
      node_exists?(state.cache, Utils.simple_hash(node_id)) ->
        {:noreply, state}

      true ->
        {:noreply, add_node(state, {node_id, address, socket})}
    end
  end

  @doc """
  This function is for debugging purpose only. It prints out the complete
  routing table.
  """
  def handle_cast(:print, state) do
    state.buckets
    |> Enum.each(fn bucket ->
      Logger.debug(inspect(bucket))
    end)

    {:noreply, state}
  end

  #####################
  # Private Functions #
  #####################

  def evaluate_node(time, cache, cache_ip, header, cluster_secret, pid) do
    cond do
      time < @response_time ->
        Node.send_ping(pid, header, cluster_secret)
        true

      time >= @response_time and Node.is_good?(pid) ->
        Node.goodness(pid, :questionable)
        Node.send_ping(pid, header, cluster_secret)
        true

      time >= @response_time and Node.is_questionable?(pid) ->
        Logger.debug("[#{Utils.encode_human(Node.id(pid))}] Deleted")
        :ets.delete(cache, Node.id(pid))
        {_, ip, port} = Node.to_tuple(pid)
        :ets.delete(cache_ip, {ip, port})
        Node.stop(pid)
        false
    end
  end

  def find_node_on_random_node(target, state) do
    case random_node(state.cache) do
      {node_id, {node_pid, _}} when is_pid(node_pid) ->
        if Process.alive?(node_pid) do
          node = Node.to_tuple(node_pid)
          socket = Node.socket(node_pid)

          ## Start find_node search
          state.node_id_enc
          |> CrissCrossDHT.Registry.get_pid(CrissCrossDHT.Search.Supervisor)
          |> CrissCrossDHT.Search.Supervisor.start_child(
            :find_node,
            socket,
            state.original_node_id,
            state.node_id_enc,
            state.ip_tuple,
            state.cluster_secret
          )
          |> Search.find_node(state.cluster, target: target, start_nodes: [node])
        else
          new_bucket = del_node(state.cache, state.cache_ip, state.buckets, node_id)
          find_node_on_random_node(target, %{state | buckets: new_bucket})
        end

      nil ->
        Logger.warn(
          "No nodes in our routing table for cluster #{Utils.encode_human(state.cluster)}."
        )
    end
  end

  @doc """
  This function adds a new node to our routing table.
  """
  def add_node(state, node_tuple) do
    {node_id, ip_port, _socket} = node_tuple

    my_node_id = state.node_id
    buckets = state.buckets
    hashed_id = Utils.simple_hash(node_id)

    index = find_bucket_index(buckets, my_node_id, hashed_id)
    bucket = Enum.at(buckets, index)

    cond do
      ## If the bucket has still some space left, we can just add the node to
      ## the bucket. Easy Peasy
      Bucket.has_space?(bucket) ->
        node_child =
          {Node, own_node_id: state.original_node_id, node_tuple: node_tuple, bucket_index: index}

        {:ok, pid} =
          state.node_id_enc
          |> CrissCrossDHT.Registry.get_pid(
            CrissCrossDHT.RoutingTable.NodeSupervisor,
            state.rt_name
          )
          |> DynamicSupervisor.start_child(node_child)

        new_bucket = Bucket.add(bucket, pid)
        :ets.insert(state.cache, {hashed_id, {pid, ip_port}})
        :ets.insert(state.cache_ip, {ip_port, pid})
        state |> Map.put(:buckets, List.replace_at(buckets, index, new_bucket))

      ## If the bucket is full and the node would belong to a bucket that is far
      ## away from us, we will just drop that node. Go away you filthy node!
      Bucket.is_full?(bucket) and index != index_last_bucket(buckets) ->
        Logger.debug(
          "Bucket #{index} is full -> drop #{Utils.encode_human(state.original_node_id)}"
        )

        state

      ## If the bucket is full but the node is closer to us, we will reorganize
      ## the nodes in the buckets and try again to add it to our bucket list.
      true ->
        buckets = reorganize(bucket.nodes, buckets ++ [Bucket.new(index + 1)], my_node_id)
        add_node(%{state | :buckets => buckets}, node_tuple)
    end
  end

  @doc """
  TODO
  """
  def reorganize([], buckets, _self_node_id), do: buckets

  def reorganize([node | rest], buckets, my_node_id) do
    current_index = length(buckets) - 2
    index = find_bucket_index(buckets, my_node_id, Node.hashed_id(node))

    new_buckets =
      if current_index != index do
        current_bucket = Enum.at(buckets, current_index)
        new_bucket = Enum.at(buckets, index)

        ## Remove the node from the current bucket
        filtered_bucket = Bucket.del(current_bucket, Node.hashed_id(node))

        ## Change bucket index in the Node to the new one
        Node.bucket_index(node, index)

        ## Then add it to the new_bucket
        List.replace_at(buckets, current_index, filtered_bucket)
        |> List.replace_at(index, Bucket.add(new_bucket, node))
      else
        buckets
      end

    reorganize(rest, new_buckets, my_node_id)
  end

  @doc """
  This function returns a random node pid. If the routing table is empty it
  returns nil.
  """
  def random_node(cache) do
    cache |> :ets.tab2list() |> Enum.random()
  rescue
    _e in Enum.EmptyError -> nil
  end

  @doc """
  Returns the index of the last bucket as integer.
  """
  def index_last_bucket(buckets) do
    Enum.count(buckets) - 1
  end

  @doc """
  TODO
  """
  def find_bucket_index(buckets, self_node_id, remote_node_id) do
    unless byte_size(self_node_id) == byte_size(remote_node_id) do
      Logger.error("self_node_id: #{byte_size(self_node_id)}
      remote_node_id: #{byte_size(remote_node_id)}")

      raise ArgumentError, message: "Different length of self_node_id and remote_node_id"
    end

    bucket_index = Distance.find_bucket(self_node_id, remote_node_id)

    min(bucket_index, index_last_bucket(buckets))
  end

  @doc """
  TODO
  """
  def node_exists?(cache, node_id), do: get_node(cache, node_id)

  @doc """
  TODO
  """
  def del_node(cache, cache_ip, buckets, node_id) do
    {_id, {node_pid, ip_tuple}} = :ets.lookup(cache, node_id) |> Enum.at(0)

    ## Delete node from the bucket list
    new_buckets =
      Enum.map(buckets, fn bucket ->
        Bucket.del(bucket, node_id)
      end)

    ## Delete node from the ETS cache
    :ets.delete(cache, node_id)

    ## Stop the node

    Node.stop(node_pid)
    :ets.delete(cache_ip, ip_tuple)

    new_buckets
  end

  @doc """

  """
  def get_node(cache, node_id) do
    case :ets.lookup(cache, node_id) do
      [{_node_id, {pid, _}} | _] ->
        if Process.alive?(pid) do
          pid
        else
          :ets.delete(cache, node_id)
          nil
        end

      [] ->
        nil
    end
  end

  def get_node_ip(cache_ip, ip_tuple) do
    case :ets.lookup(cache_ip, ip_tuple) do
      [{_node_id, pid} | _] ->
        if Process.alive?(pid) do
          pid
        else
          :ets.delete(cache_ip, ip_tuple)
          nil
        end

      [] ->
        nil
    end
  end
end
