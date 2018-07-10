defmodule LWF do
  require Logger

  @proposals_url "https://devel.lwf.io/delegates"

  def transactions(params, %{"host" => h, "port" => p}) do
    url = "http://#{h}:#{p}/api/transactions#{params}"

    with {:ok, resp} <- HTTPoison.get(url),
         {:ok, res} <- Jason.decode(resp.body),
         true <- res["success"] do
      {:ok, res["transactions"]}
    else
      err -> err
    end
  end

  def votes(address, %{"host" => h, "port" => p}) do
    url = "http://#{h}:#{p}/api/accounts/delegates?address=#{address}"

    with {:ok, response} <- HTTPoison.get(url),
         {:ok, results} <- Jason.decode(response.body) do
      Enum.map(results["delegates"], fn d -> d["username"] end)
    else
      _err ->
        []
    end
  end

  def proposals() do
    headers = [Accept: "application/json; charset=utf-8"]

    with {:ok, response} <- HTTPoison.get(@proposals_url, headers, hackney: [:insecure]),
         {:ok, results} <- Jason.decode(response.body) do
      results["delegates"]
    else
      _err ->
        []
    end
  end

  def broadcast(%{wallet: wallet, second_sign_key: ssk, net: net}, pools) do
    votes = Enum.map(pools, fn {_, key} -> "-" <> key end)

    tx =
      Dpos.Tx.Vote.build(%{
        fee: 100_000_000,
        timestamp: Dpos.Time.now(),
        senderPublicKey: wallet.pub_key,
        recipientId: wallet.address,
        asset: %{votes: votes}
      })

    tx = Dpos.Tx.sign(tx, wallet, ssk)

    case Dpos.Net.broadcast(tx, net["name"], host: net["host"]) do
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
end
