# Portfolio

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Admin access

`/admin` is only available to users with a confirmed email address, and it is not linked from the site. There is no admin functionality yet.

Production email delivery is not configured, so confirmation emails are only viewable at `http://localhost:4000/dev/mailbox` in development. To confirm your own account and set a password without email, run this in IEx against the target environment (the password must be at least 12 characters):

```elixir
alias Portfolio.{Repo, Accounts}
alias Portfolio.Accounts.User

user = Repo.get_by!(User, email: "you@example.com")

user =
  user
  |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  |> Repo.update!()

{:ok, _} = Accounts.update_user_password(user, %{password: "change-me-now"})
```
