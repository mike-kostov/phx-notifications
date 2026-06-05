defmodule PhxNotifications.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      alias PhxNotifications.{TestRepo, TestUser}
      import PhxNotifications.DataCase
    end
  end

  setup do
    # Tests are serial (async: false) over a single SQLite connection; start each from a
    # clean slate instead of using the sandbox.
    PhxNotifications.TestRepo.delete_all(PhxNotifications.Notification)
    PhxNotifications.TestRepo.delete_all(PhxNotifications.TestUser)
    :ok
  end

  @doc "Inserts and returns a persisted recipient user."
  def user_fixture(attrs \\ %{}) do
    name = Map.get(attrs, :name, "user-#{System.unique_integer([:positive])}")

    PhxNotifications.TestRepo.insert!(%PhxNotifications.TestUser{name: name})
  end

  @doc "Collects changeset validation errors into a `%{field => [messages]}` map."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
