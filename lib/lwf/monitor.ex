defmodule LWF.Monitor do
  use GenServer
  require Logger

  @config_path "config.json"
  # interval expressed in seconds
  @interval 300
  # buffers expressed in hours
  @buffers %{"daily" => 12, "weekly" => 24, "monthly" => 48}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    case load_config() do
      {:ok, state} ->
        send(self(), :fetch_pools)
        {:ok, state}

      error ->
        print_error(error)
        :ignore
    end
  end

  def handle_info(:fetch_pools, state) do
    clear_screen()

    voted_pools = LWF.votes(state.wallet.address, state.net)
    proposals = LWF.proposals(state.net)

    Enum.each(voted_pools, fn name ->
      unless proposals[name], do: Logger.warn("⚡ Delegate #{name} hasn't submitted a proposal.")
    end)

    pools =
      proposals
      |> Map.take(voted_pools)
      |> Enum.filter(fn {_, prop} -> prop["delegate_type"] != 'public_pool' end)

    print_pools(pools)

    send(self(), :work)

    {:noreply, Map.put(state, :pools, pools)}
  end

  def handle_info(:work, state) do
    Enum.each(state.pools, fn {pool, prop} ->
      send(self(), {:check_pool, pool, prop})
    end)

    send(self(), :unvote)

    Process.send_after(self(), :fetch_pools, state.interval * 1000)

    {:noreply, state}
  end

  def handle_info({:check_pool, pool, prop}, state) do
    with true <- is_active?(pool, prop),
         false <- is_blacklisted?(pool, state.blacklist),
         true <- has_paid_in_time?(pool, prop, state) do
      {:noreply, state}
    else
      :unvote ->
        pool = {pool, prop["publicKey"]}
        {:noreply, queue_bad_pool(state, pool)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(:unvote, %{pool_queue: []} = state), do: {:noreply, state}

  def handle_info(:unvote, %{autounvote: true} = state) do
    print_bad_pools("Unvoting the following pools:", state.pool_queue)

    chunks = Enum.chunk_every(state.pool_queue, 25)

    Enum.each(chunks, fn chunk ->
      send(self(), {:unvote_chunk, chunk})
    end)

    {:noreply, state}
  end

  def handle_info(:unvote, state) do
    "Bad pools detected! You should either unvote them manually or enable auto unvoting:"
    |> print_bad_pools(state.pool_queue)

    {:noreply, state}
  end

  def handle_info({:unvote_chunk, chunk}, state) do
    case LWF.broadcast(state, chunk) do
      :ok ->
        pool_queue = state.pool_queue -- chunk
        {:noreply, %{state | pool_queue: pool_queue}}

      :error ->
        {:noreply, state}
    end
  end

  defp is_active?(_pool, %{"rank" => x}) when x <= 201, do: true

  defp is_active?(pool, _prop) do
    Logger.warn("Pool #{pool} is not active. Skipping.")
    false
  end

  defp is_blacklisted?(pool, blacklist) do
    if Enum.member?(blacklist, pool) do
      Logger.warn("Pool #{pool} is blacklisted. Skipping.")
      true
    else
      false
    end
  end

  defp has_paid_in_time?(pool, prop, %{wallet: wallet, buffers: buffers, net: net}) do
    payout_address = prop["payout_address"]
    my_address = wallet.address

    params = "?senderId=#{payout_address}&orderBy=timestamp:desc"

    with {:ok, txs} <- LWF.transactions(params, net),
         true <- check_payout_tx(prop, my_address, txs, buffers) do
      Logger.info("✓ Pool #{pool} has paid in time.")
      true
    else
      false ->
        Logger.warn("✖ Pool #{pool} hasn't paid in time.")
        :unvote

      {:error, _msg} ->
        Logger.error("Unable to reach node. Skipping.")
        false
    end
  end

  defp check_payout_tx(_prop, _rcpt, [], _buffers), do: false

  defp check_payout_tx(prop, rcpt, txs, buffers) do
    tx = Enum.find(txs, fn t -> t["recipientId"] == rcpt end)
    now = Dpos.Time.now()

    interval =
      case prop["payout_interval"] do
        1 -> "daily"
        7 -> "weekly"
        31 -> "monthly"
      end

    payout_freq = prop["payout_interval"] * 24 * 60 * 60
    buffer = buffers[interval] * 60 * 60

    cond do
      is_nil(tx) ->
        false

      now - tx["timestamp"] > payout_freq + buffer ->
        false

      true ->
        true
    end
  end

  defp queue_bad_pool(state, pool) do
    if Enum.member?(state.pool_queue, pool) do
      state
    else
      pool_queue = [pool | state.pool_queue]
      %{state | pool_queue: pool_queue}
    end
  end

  defp generate_keypair(""), do: nil
  defp generate_keypair(nil), do: nil

  defp generate_keypair(secret) when is_binary(secret) do
    {sk, _} = Dpos.Utils.generate_keypair(secret)
    sk
  end

  defp load_config() do
    with {:ok, file} <- File.read(@config_path),
         {:ok, config} <- Jason.decode(file),
         wallet <- Dpos.Wallet.generate_lwf(config["passphrase"]) do
      state = %{
        pool_queue: [],
        wallet: wallet,
        second_sign_key: generate_keypair(config["secondphrase"]),
        net: config["net"],
        autounvote: config["autounvote"],
        interval: config["interval"] || @interval,
        buffers: parse_buffers(config["buffers"]),
        blacklist: config["blacklist"]
      }

      {:ok, state}
    end
  end

  defp parse_buffers(nil), do: @buffers

  defp parse_buffers(buffers) when is_map(buffers) do
    Map.merge(@buffers, buffers)
  end

  defp clear_screen(), do: IO.write("\e[0;0H\e[2J")

  defp print_pools([]), do: true

  defp print_pools(pools) do
    Logger.info("Loading pools:")

    Enum.each(pools, fn {k, _v} ->
      Logger.info("• #{k}")
    end)
  end

  defp print_bad_pools(msg, pools) do
    Logger.warn(msg)

    Enum.each(pools, fn {k, _v} ->
      Logger.warn("• #{k}")
    end)
  end

  defp print_error({:error, :enoent}) do
    Logger.error("Unable to open configuration file #{@config_path}. Aborting.")
  end

  defp print_error({:error, %Jason.DecodeError{}}) do
    Logger.error("Syntax error detected in #{@config_path}. Aborting.")
  end

  defp print_error(unknown) do
    Logger.error("Unknown error: #{inspect(unknown)}")
  end
end
