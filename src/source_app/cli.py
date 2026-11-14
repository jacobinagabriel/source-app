import argparse
import asyncio
import logging

from faker import Faker

from source_app.admin import init_database
from source_app.settings import AdminSettings, DatabaseSettings, SimulationSettings
from source_app.simulator import TheLookECommSimulator

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s")

# Flags default to None so that only flags given on the command line override the
# environment (DB_* / SIM_*) and the settings defaults.
DB_FLAGS = {
    "--db-host": ("host", str, "Database host."),
    "--db-port": ("port", int, "Database port."),
    "--db-name": ("name", str, "Database name."),
    "--db-user": ("user", str, "Database user."),
    "--db-password": ("password", str, "Database password (prefer DB_PASSWORD)."),
    "--db-schema": ("schema_name", str, "Database schema."),
}

ADMIN_FLAGS = {
    "--db-admin-user": ("user", str, "Admin user that creates the app user (db-init only)."),
    "--db-admin-password": ("password", str, "Admin password (prefer DB_ADMIN_PASSWORD)."),
}

SIM_FLAGS = {
    "--avg-qps": ("avg_qps", float, "Average purchases per second."),
    "--max-iter": ("max_iter", int, "Stop after this many iterations (-1 runs forever)."),
    "--init-num-users": ("init_num_users", int, "Users created by `seed`."),
    "--country": ("country", str, "User country."),
    "--state": ("state", str, "User state."),
    "--postal-code": ("postal_code", str, "User postal code."),
    "--user-create-prob": ("user_create_prob", float, "Probability of a new user."),
    "--user-update-prob": ("user_update_prob", float, "Probability of a user address change."),
    "--order-update-prob": ("order_update_prob", float, "Probability of an order status change."),
    "--ghost-create-prob": ("ghost_create_prob", float, "Probability of an anonymous session."),
    "--order-delete-prob": (
        "order_delete_prob",
        float,
        "Probability of deleting a cancelled order.",
    ),
    "--ghost-purge-prob": (
        "ghost_purge_prob",
        float,
        "Probability of purging old anonymous events.",
    ),
    "--ghost-retention-minutes": (
        "ghost_retention_minutes",
        int,
        "Anonymous events older than this can be purged.",
    ),
    "--ghost-purge-batch": ("ghost_purge_batch", int, "Max anonymous events deleted per purge."),
}


def _add_flags(parser: argparse.ArgumentParser, flags: dict) -> None:
    for flag, (dest, type_, help_) in flags.items():
        parser.add_argument(flag, dest=dest, type=type_, default=None, help=help_)


def _overrides(args: argparse.Namespace, flags: dict) -> dict:
    values = {dest: getattr(args, dest) for dest, _, _ in flags.values()}
    return {k: v for k, v in values.items() if v is not None}


def build_parser() -> argparse.ArgumentParser:
    db_parent = argparse.ArgumentParser(add_help=False)
    _add_flags(db_parent, DB_FLAGS)
    admin_parent = argparse.ArgumentParser(add_help=False)
    _add_flags(admin_parent, ADMIN_FLAGS)
    sim_parent = argparse.ArgumentParser(add_help=False)
    _add_flags(sim_parent, SIM_FLAGS)

    parser = argparse.ArgumentParser(
        prog="source-app", description="Generate theLook eCommerce traffic in PostgreSQL."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser(
        "db-init",
        parents=[db_parent, admin_parent],
        help="As the admin, create the app user (DB_USER) and grant it the schema.",
    )
    commands.add_parser(
        "migrate",
        parents=[db_parent],
        help="Apply database migrations (schema and reference data).",
    )
    commands.add_parser("seed", parents=[db_parent, sim_parent], help="Create the initial users.")
    commands.add_parser("run", parents=[db_parent, sim_parent], help="Generate traffic.")
    return parser


async def _dispatch(command: str, simulator: TheLookECommSimulator) -> None:
    try:
        if command == "migrate":
            await simulator.migrate()
        elif command == "seed":
            await simulator.seed()
        else:
            await simulator.run()
    except asyncio.CancelledError:
        logging.warning("Data generation task was cancelled.")
    finally:
        await simulator.close()


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    db = DatabaseSettings(**_overrides(args, DB_FLAGS))
    if args.command == "db-init":
        admin = AdminSettings(**_overrides(args, ADMIN_FLAGS))
        logging.info(f"command=db-init db={db!r} admin_user={admin.user}")
        init_database(db, admin)
        return

    sim = SimulationSettings(**_overrides(args, SIM_FLAGS) if args.command != "migrate" else {})
    logging.info(f"command={args.command} db={db!r} sim={sim!r}")

    try:
        asyncio.run(_dispatch(args.command, TheLookECommSimulator(db, sim, Faker())))
    except KeyboardInterrupt:
        logging.warning("Data generator stopped by user.")


if __name__ == "__main__":
    main()
