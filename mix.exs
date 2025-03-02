defmodule CrissCrossDHT.Mixfile do
  use Mix.Project

  def project do
    [
      app: :criss_cross_dht,
      version: "0.0.1",
      elixir: "~> 1.12",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:b58, "~> 1.0.2"},
      {:ex_schnorr, "~> 0.1.1"},
      {:ex_doc, "~> 0.19", only: :dev},
      {:pretty_hex, "~> 0.0.1", only: :dev},
      {:dialyxir, "~> 0.5.1", only: [:dev, :test]},
      {:ex_multihash, "~> 2.0"},
      {:sorted_set_kv, "~> 0.1.3"},
      {:redix, github: "SoCal-Software-Labs/safe-redix"},
      {:cachex, "~> 3.4.0"},
      # {:ex_p2p, path: "../ex_p2p"},
      {:ex_p2p,
       github: "SoCal-Software-Labs/ExP2P", ref: "2104c37904e89f32ea84418fd002d19efe4c4bfb"},
      {:yaml_elixir, "~> 2.8"},
      {:file_system, "~> 0.2.10"}
    ]
  end

  defp description do
    """
    Distributed Hash Table (DHT) is a storage and lookup system based on a peer-to-peer (P2P) system for CrissCross.
    """
  end

  defp package do
    [
      name: :criss_cross_dht,
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Kyle Hanson"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/SoCal-Software-Labs/CrissCrossDHT"}
    ]
  end
end
