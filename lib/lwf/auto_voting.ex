defmodule LWF.AutoVoting do
  use GenServer
  require Logger

  @config_path "config.json"
  @default_net "lwf"
  # interval expressed in seconds
  @interval 30
  # buffers expressed in hours
  @buffers %{"daily" => 12, "weekly" => 24, "monthly" => 48}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    with {:ok, file} <- File.read(@config_path),
         {:ok, config} <- Jason.decode(file),
         wallet <- Dpos.Wallet.generate_lwf(config["passphrase"]) do
      send(self(), :fetch_pools)
      send(self(), :work)

      state = %{
        pool_queue: [],
        wallet: wallet,
        second_sign_key: generate_keypair(config["secondphrase"]),
        net: config["net"] || @default_net,
        interval: config["interval"] || @interval,
        buffers: parse_buffers(config["buffers"]),
        blacklist: config["blacklist"]
      }

      {:ok, state}
    else
      error ->
        print_error(error)
        :ignore
    end
  end

  def handle_info(:fetch_pools, state) do
    voted_delegates = LWF.votes(state.wallet.address)
    proposals = LWF.proposals()

    pools =
      proposals
      |> Map.take(voted_delegates)
      |> Enum.filter(fn {_, prop} -> prop["delegate_type"] != 'public_pool' end)

    print_pools(pools)

    {:noreply, Map.put(state, :pools, pools)}
  end

  def handle_info(:work, state) do
    Enum.each(state.pools, fn {pool, prop} ->
      send(self(), {:check_pool, pool, prop})
    end)

    send(self(), :unvote)

    Process.send_after(self(), :fetch_pools, state.interval * 1000)
    Process.send_after(self(), :work, state.interval * 1000)

    {:noreply, state}
  end

  def handle_info({:check_pool, pool, prop}, state) do
    Logger.info("Checking pool #{pool}.")

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

  def handle_info(:unvote, state) do
    print_votes(state.pool_queue)
    chunks = Enum.chunk_every(state.pool_queue, 25)

    Enum.each(chunks, fn chunk ->
      send(self(), {:unvote_chunk, chunk})
    end)

    {:noreply, state}
  end

  def handle_info({:unvote_chunk, chunk}, state) do
    case send_tx(state, chunk) do
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

  defp has_paid_in_time?(pool, prop, %{wallet: wallet, buffers: buffers}) do
    payout_address = prop["payout_address"]
    my_address = wallet.address

    params = "?senderId=#{payout_address}&orderBy=timestamp:desc"

    with {:ok, txs} <- LWF.transactions(params),
         true <- check_payout_tx(prop, my_address, txs, buffers) do
      Logger.info("Pool #{pool} has paid in time.")
      true
    else
      false ->
        Logger.error("Pool #{pool} hasn't paid in time. Unvoting.")
        :unvote

      {:error, _msg} ->
        Logger.warn("Unable to reach node. Skipping.")
        false
    end
  end

  defp check_payout_tx(_prop, _rcpt, []) do
    false
  end

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

  defp send_tx(%{wallet: wallet, net: net} = state, pools) do
    votes = Enum.map(pools, fn {_, key} -> "-" <> key end)

    tx =
      Dpos.Tx.Vote.build(%{
        fee: 100_000_000,
        timestamp: Dpos.Time.now(),
        senderPublicKey: wallet.pub_key,
        recipientId: wallet.address,
        asset: %{votes: votes}
      })
      |> Dpos.Tx.sign(wallet, state.second_sign_key)

    case Dpos.Net.broadcast(tx, net) do
      {:error, %HTTPoison.Error{reason: r}} ->
        Logger.error("TX error: #{inspect(r)}")
        :error

      {:error, err} ->
        Logger.error("TX error: #{inspect(err)}")
        :error

      _ ->
        :ok
    end
  end

  defp generate_keypair(""), do: nil
  defp generate_keypair(nil), do: nil

  defp generate_keypair(secret) when is_binary(secret) do
    {sk, _} = Dpos.Utils.generate_keypair(secret)
    sk
  end

  defp parse_buffers(nil), do: @buffers

  defp parse_buffers(buffers) when is_map(buffers) do
    Map.merge(@buffers, buffers)
  end

  defp print_pools([]), do: true

  defp print_pools(pools) do
    Logger.info("Loading pools:")
    Enum.each(pools, fn {k, _v} -> Logger.info("- #{k}") end)
  end

  defp print_votes([]), do: true

  defp print_votes(pools) do
    Logger.error("Unvoting the following pools:")
    Enum.each(pools, fn {name, _} -> Logger.error("- #{name}") end)
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
