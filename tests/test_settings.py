from source_app.cli import DB_FLAGS, SIM_FLAGS, _overrides, build_parser
from source_app.settings import DatabaseSettings, SimulationSettings


def test_env_vars_are_read(monkeypatch):
    monkeypatch.setenv("DB_HOST", "db.internal")
    monkeypatch.setenv("DB_SCHEMA", "shop")
    monkeypatch.setenv("SIM_AVG_QPS", "5")

    db = DatabaseSettings()
    assert db.host == "db.internal"
    assert db.schema_name == "shop"
    assert SimulationSettings().avg_qps == 5


def test_flags_override_env(monkeypatch):
    monkeypatch.setenv("DB_HOST", "from-env")
    monkeypatch.setenv("DB_SCHEMA", "from-env")
    args = build_parser().parse_args(
        ["run", "--db-host", "from-flag", "--db-schema", "flagged", "--avg-qps", "3"]
    )

    db = DatabaseSettings(**_overrides(args, DB_FLAGS))
    sim = SimulationSettings(**_overrides(args, SIM_FLAGS))
    assert db.host == "from-flag"
    assert db.schema_name == "flagged"
    assert sim.avg_qps == 3
    assert sim.order_update_prob == 0.4  # untouched default


def test_password_is_not_logged():
    db = DatabaseSettings(password="s3cr3t!@#")
    assert "s3cr3t" not in repr(db)
    # URL.create escapes special characters instead of breaking the connection string.
    assert db.url().password == "s3cr3t!@#"
