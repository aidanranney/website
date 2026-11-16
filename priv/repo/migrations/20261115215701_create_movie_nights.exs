defmodule Portfolio.Repo.Migrations.CreateMovieNights do
  use Ecto.Migration

  def change do
    create table(:movie_nights, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :starts_at, :naive_datetime, null: false
      add :note, :string
      add :phase, :string, null: false, default: "nominating"
      timestamps(type: :utc_datetime)
    end

    create table(:candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :movie_night_id, references(:movie_nights, type: :binary_id, on_delete: :delete_all),
        null: false

      add :nominated_by_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tmdb_id, :integer, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:candidates, [:movie_night_id, :tmdb_id])

    create table(:votes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :candidate_id, references(:candidates, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:votes, [:candidate_id, :user_id])
    create index(:votes, [:user_id])
  end
end
