defmodule Portfolio.MovieNights.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "votes" do
    belongs_to :candidate, Portfolio.MovieNights.Candidate
    belongs_to :user, Portfolio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [])
    |> unique_constraint([:candidate_id, :user_id])
  end
end
