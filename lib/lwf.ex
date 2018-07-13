defmodule LWF do
  require Logger

  @mainnet_proposals "https://www.lwf.io/delegates"
  @testnet_proposals "https://devel.lwf.io/delegates"

  def transactions(params, %{"host" => h, "port" => p}) do
    url = "http://#{h}:#{p}/api/transactions#{params}"

    with {:ok, response} <- HTTPoison.get(url),
         200 <- response.status_code,
         {:ok, results} <- Jason.decode(response.body),
         true <- results["success"] do
      {:ok, results["transactions"]}
    else
      err -> err
    end
  end

  def votes(address, %{"host" => h, "port" => p}) do
    url = "http://#{h}:#{p}/api/accounts/delegates?address=#{address}"

    with {:ok, response} <- HTTPoison.get(url),
         200 <- response.status_code,
         {:ok, results} <- Jason.decode(response.body),
         true <- results["success"] do
      Enum.map(results["delegates"], fn d -> d["username"] end)
    else
      _err ->
        Logger.error("Unable to fetch voted delegates.")
        []
    end
  end

  def proposals(net) do
    headers = [Accept: "application/json; charset=utf-8"]

    url =
      if net["name"] == "lwf" do
        @mainnet_proposals
      else
        @testnet_proposals
      end

    with {:ok, response} <- HTTPoison.get(url, headers, hackney: [:insecure]),
         200 <- response.status_code,
         {:ok, results} <- Jason.decode(response.body) do
      results["delegates"] || %{}
    else
      _err ->
        Logger.error("Unable to fetch proposals.")
        %{}
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
