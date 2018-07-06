defmodule LWF do
  # @node_host "http://node1.lwf.io:18124"
  @node_host "http://testnode1.lwf.io:18101"
  @proposals_url "https://devel.lwf.io/delegates"

  def transactions(params) do
    url = "#{@node_host}/api/transactions#{params}"

    with {:ok, resp} <- HTTPoison.get(url),
         {:ok, res} <- Jason.decode(resp.body),
         true <- res["success"] do
      {:ok, res["transactions"]}
    else
      err -> err
    end
  end

  def votes(address) do
    url = "#{@node_host}/api/accounts/delegates?address=#{address}"

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
end
