defmodule PhxNotifications.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mike-kostov/phx_notifications"

  def project do
    [
      app: :phx_notifications,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "PhxNotifications",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # === Required ===
      {:ecto_sql, "~> 3.12"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},

      # === Optional: in-app Bell LiveComponent ===
      {:phoenix_live_view, "~> 1.0", optional: true},

      # === Optional: Oban-backed delivery strategy ===
      {:oban, "~> 2.18", optional: true},

      # === Test ===
      {:ecto_sqlite3, "~> 0.17", only: :test}
    ]
  end

  defp description do
    "A drop-in, self-contained in-app notification system for Phoenix: bell icon, " <>
      "unread counts, PubSub wiring, and read-state handling out of the box."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
