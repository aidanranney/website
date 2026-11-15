# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Portfolio.Repo.insert!(%Portfolio.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# To confirm an account and set a password without email delivery, run in IEx:
#
#     alias Portfolio.{Repo, Accounts}
#     alias Portfolio.Accounts.User
#     user = Repo.get_by!(User, email: "you@example.com")
#     user = user |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)) |> Repo.update!()
#     {:ok, _} = Accounts.update_user_password(user, %{password: "change-me-now"})
