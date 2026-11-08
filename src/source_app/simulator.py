import asyncio
import datetime
import logging
import random
import threading
from collections import Counter

from alembic import command
from alembic.config import Config
from faker import Faker
from sqlalchemy.exc import OperationalError, SQLAlchemyError

from source_app import repository
from source_app.db import make_sessionmaker
from source_app.models import Event, EventCategory, Order, OrderItem, OrderStatus, User
from source_app.settings import DatabaseSettings, SimulationSettings

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s")


class TheLookECommSimulator:
    """
    Manages the state and execution of the e-commerce data generation simulation.

    Every business action (a purchase, a status change, a new user, an anonymous
    session) runs in its own session and commits as one transaction.
    """

    def __init__(self, db: DatabaseSettings, sim: SimulationSettings, fake: Faker):
        self.db = db
        self.sim = sim
        self.fake = fake
        self.Session = make_sessionmaker(db)
        self.consecutive_db_errors = 0
        self.max_consecutive_errors = 3
        # Committed business actions by type, logged periodically and at the end of `run`.
        self.stats: Counter[str] = Counter()
        self._stats_lock = threading.Lock()

    def _count(self, action: str, n: int = 1) -> None:
        with self._stats_lock:
            self.stats[action] += n

    async def migrate(self):
        """Applies all Alembic migrations (schema and reference data)."""
        config = Config()
        config.set_main_option("script_location", "source_app:migrations")
        config.attributes["db_settings"] = self.db
        logging.info("Upgrading the database to the latest revision...")
        await asyncio.to_thread(command.upgrade, config, "head")
        logging.info("Database is at the latest revision.")

    async def seed(self):
        """Creates the initial users. Reference data comes from the migrations."""
        users = [self._new_user() for _ in range(self.sim.init_num_users)]
        logging.info(f"Writing {len(users)} initial users...")
        await asyncio.to_thread(self._add_all, users)
        logging.info("Seeding finished.")

    def _new_user(self) -> User:
        return User.new(
            country=self.sim.country,
            state=self.sim.state,
            postal_code=self.sim.postal_code,
            fake=self.fake,
        )

    def _add_all(self, rows: list) -> None:
        with self.Session.begin() as session:
            session.add_all(rows)

    def _simulate_purchase(self) -> None:
        """Writes a new order, its items and the events leading to it."""
        address_updated = False
        with self.Session.begin() as session:
            user = repository.random_user(session)
            if user is None:
                logging.warning("No users found. Skipping a purchase; run `seed` first.")
                return

            # Potentially update the user's address
            if self.sim.user_update_prob > 0 and random.random() < self.sim.user_update_prob:
                logging.info("Updating a user address...")
                user.update_address(
                    country=self.sim.country,
                    state=self.sim.state,
                    postal_code=self.sim.postal_code,
                    fake=self.fake,
                )
                address_updated = True

            order = Order.new(user=user, fake=self.fake)
            for _ in range(order.num_of_items):
                item = OrderItem.new(order=order, fake=self.fake)
                session.add_all(
                    Event.new(
                        user=user,
                        order_item=item,
                        event_category=EventCategory.PURCHASE.value,
                        fake=self.fake,
                    )
                )
            session.add(order)
        self._count("order_created")
        if address_updated:
            self._count("user_address_updated")

    def _simulate_order_update(self):
        """Moves a random order to its next status, with cancel/return events."""
        with self.Session.begin() as session:
            order = repository.random_order(session)
            if order is None:
                logging.warning("No orders found. Skipping an order status update.")
                return

            previous_status = order.status
            order.update_status(fake=self.fake)
            for item in order.items:
                item.update_status(order=order)

                event_category = None
                if item.status == OrderStatus.CANCELLED.value:
                    event_category = EventCategory.CANCEL.value
                elif item.status == OrderStatus.RETURNED.value:
                    event_category = EventCategory.RETURN.value

                if event_category:
                    session.add_all(
                        Event.new(
                            user=order.user,
                            order_item=item,
                            event_category=event_category,
                            fake=self.fake,
                        )
                    )
        if order.status != previous_status:
            self._count("order_status_updated")

    def _create_user(self) -> None:
        self._add_all([self._new_user()])
        self._count("user_created")

    def _create_ghost_session(self) -> None:
        self._add_all(
            Event.new(
                user=None,
                order_item=None,
                event_category=EventCategory.GHOST.value,
                fake=self.fake,
            )
        )
        self._count("ghost_session_created")

    async def _simulate_side_tasks(self):
        """Runs secondary simulation events based on their respective probabilities."""
        side_tasks = []

        if self.sim.user_create_prob > 0 and random.random() < self.sim.user_create_prob:
            logging.info("Creating a new user...")
            side_tasks.append(asyncio.to_thread(self._create_user))

        if self.sim.ghost_create_prob > 0 and random.random() < self.sim.ghost_create_prob:
            logging.info("Creating a ghost event...")
            side_tasks.append(asyncio.to_thread(self._create_ghost_session))

        if self.sim.order_update_prob > 0 and random.random() < self.sim.order_update_prob:
            logging.info("Update an order status...")
            side_tasks.append(asyncio.to_thread(self._simulate_order_update))

        if self.sim.order_delete_prob > 0 and random.random() < self.sim.order_delete_prob:
            side_tasks.append(asyncio.to_thread(self._delete_cancelled_order))

        if self.sim.ghost_purge_prob > 0 and random.random() < self.sim.ghost_purge_prob:
            side_tasks.append(asyncio.to_thread(self._purge_ghost_events))

        if side_tasks:
            await asyncio.gather(*side_tasks)

    def _delete_cancelled_order(self) -> None:
        """Deletes a random cancelled order; the database cascades to its items."""
        with self.Session.begin() as session:
            order = repository.random_cancelled_order(session)
            if order is None:
                return
            logging.info(f"Deleting cancelled order {order.id}...")
            session.delete(order)
        self._count("order_deleted")

    def _purge_ghost_events(self) -> None:
        """Deletes a batch of anonymous events past their retention."""
        with self.Session.begin() as session:
            deleted = repository.purge_ghost_events(
                session,
                older_than=datetime.timedelta(minutes=self.sim.ghost_retention_minutes),
                limit=self.sim.ghost_purge_batch,
            )
        if deleted:
            logging.info(f"Purged {deleted} old anonymous events.")
        self._count("ghost_event_purged", deleted)

    def log_stats(self) -> None:
        summary = ", ".join(f"{k}={v}" for k, v in sorted(self.stats.items()))
        logging.info(f"Actions so far: {summary or 'none'}")

    async def run(self):
        """The main simulation loop, which orchestrates primary and side tasks."""
        current_iteration = 0
        while True:
            if 0 < self.sim.max_iter <= current_iteration:
                logging.info(
                    f"Stopping data generation after reaching {current_iteration} iterations."
                )
                break

            try:
                wait_time = random.expovariate(self.sim.avg_qps)
                await asyncio.sleep(wait_time)

                await asyncio.to_thread(self._simulate_purchase)
                await self._simulate_side_tasks()
            except (SQLAlchemyError, OperationalError) as e:
                self.consecutive_db_errors += 1
                logging.warning(
                    f"A database error occurred. Consecutive error count: {self.consecutive_db_errors}/{self.max_consecutive_errors}. "
                    f"Error: {e}"
                )
                if self.consecutive_db_errors >= self.max_consecutive_errors:
                    logging.critical(
                        f"Exceeded max consecutive DB error limit ({self.max_consecutive_errors}). "
                        "The simulation will now stop."
                    )
                    raise
                await asyncio.sleep(5)
            else:
                if self.consecutive_db_errors > 0:
                    logging.info(
                        "Database operation successful. Resetting consecutive error counter."
                    )
                self.consecutive_db_errors = 0
                current_iteration += 1
                if current_iteration % 1000 == 0:
                    self.log_stats()
        self.log_stats()
        logging.info("Simulation loop has finished.")

    async def close(self):
        """Disposes of the connection pool."""
        await asyncio.to_thread(self.Session.kw["bind"].dispose)
        logging.info("Database connections closed.")
