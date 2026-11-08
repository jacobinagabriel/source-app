import datetime
import logging
import random
import uuid
from collections import OrderedDict
from decimal import Decimal
from enum import Enum
from typing import Self

from faker import Faker
from sqlalchemy import BigInteger, DateTime, ForeignKey, Index, Integer, Numeric, Text, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

from source_app.utils import get_location, get_product_map

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s")


PRODUCT_MAP = get_product_map("products.csv")

Money = Numeric(12, 2)


def utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.UTC)


class Base(DeclarativeBase):
    type_annotation_map = {
        str: Text(),
        int: Integer(),
        datetime.datetime: DateTime(timezone=True),
    }


class OrderStatus(Enum):
    PROCESSING = "Processing"
    SHIPPED = "Shipped"
    DELIVERED = "Delivered"
    CANCELLED = "Cancelled"
    RETURNED = "Returned"


class EventCategory(Enum):
    PURCHASE = "purchase"
    GHOST = "ghost"
    CANCEL = "cancel"
    RETURN = "return"


class DistributionCenter(Base):
    __tablename__ = "dist_centers"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=False)
    name: Mapped[str]
    latitude: Mapped[float]
    longitude: Mapped[float]


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=False)
    cost: Mapped[Decimal] = mapped_column(Money)
    category: Mapped[str]
    name: Mapped[str | None]
    brand: Mapped[str | None]
    retail_price: Mapped[Decimal] = mapped_column(Money)
    department: Mapped[str]
    sku: Mapped[str]
    distribution_center_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("dist_centers.id"))


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    first_name: Mapped[str]
    last_name: Mapped[str]
    email: Mapped[str]
    age: Mapped[int]
    gender: Mapped[str]
    street_address: Mapped[str]
    postal_code: Mapped[str]
    city: Mapped[str]
    state: Mapped[str]
    country: Mapped[str]
    latitude: Mapped[float]
    longitude: Mapped[float]
    traffic_source: Mapped[str]
    created_at: Mapped[datetime.datetime]
    updated_at: Mapped[datetime.datetime]

    @classmethod
    def new(
        cls,
        *,
        country: str = "*",
        state: str = "*",
        postal_code: str = "*",
        fake: Faker,
    ) -> Self:
        gender = fake.random_element(elements=("M", "F"))
        first_name = fake.first_name_male() if gender == "M" else fake.first_name_female()
        last_name = fake.last_name_nonbinary()
        location = get_location(country=country, state=state, postal_code=postal_code)
        traffic_source = fake.random_choices(
            elements=OrderedDict(
                zip(
                    ["Organic", "Facebook", "Search", "Email", "Display"],
                    [0.15, 0.06, 0.7, 0.05, 0.04],
                    strict=True,
                )
            ),
            length=1,
        )[0]
        now = utcnow()
        return cls(
            id=uuid.uuid4(),
            first_name=first_name,
            last_name=last_name,
            email=f"{first_name.lower()}.{last_name.lower()}@{fake.safe_domain_name()}",
            age=random.randrange(12, 71),
            gender=gender,
            street_address=fake.street_address(),
            postal_code=location["postal_code"],
            city=location["city"],
            state=location["state"],
            country=location["country"],
            latitude=float(location["latitude"]),
            longitude=float(location["longitude"]),
            traffic_source=traffic_source,
            created_at=now,
            updated_at=now,
        )

    def update_address(
        self,
        *,
        country: str = "*",
        state: str = "*",
        postal_code: str = "*",
        fake: Faker,
    ) -> Self:
        location = get_location(country=country, state=state, postal_code=postal_code)
        self.street_address = fake.street_address()
        self.postal_code = location["postal_code"]
        self.city = location["city"]
        self.state = location["state"]
        self.country = location["country"]
        self.latitude = float(location["latitude"])
        self.longitude = float(location["longitude"])
        self.updated_at = utcnow()
        return self

    def __str__(self):
        return f"User(id={self.id}, name='{self.first_name} {self.last_name}', location='{self.country}|{self.state}|{self.city}', source='{self.traffic_source}')"


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (
        # Lets the delete task pick a random cancelled order without scanning.
        Index("ix_orders_cancelled_id", "id", postgresql_where=text("status = 'Cancelled'")),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str]
    num_of_items: Mapped[int]
    created_at: Mapped[datetime.datetime]
    updated_at: Mapped[datetime.datetime]
    returned_at: Mapped[datetime.datetime | None]
    shipped_at: Mapped[datetime.datetime | None]
    delivered_at: Mapped[datetime.datetime | None]
    cancelled_at: Mapped[datetime.datetime | None]

    user: Mapped[User] = relationship()
    items: Mapped[list["OrderItem"]] = relationship(
        back_populates="order", cascade="all, delete-orphan", passive_deletes=True
    )

    @classmethod
    def new(cls, user: User, fake: Faker) -> Self:
        now = utcnow()
        return cls(
            id=uuid.uuid4(),
            user=user,
            status=OrderStatus.PROCESSING.value,
            num_of_items=fake.random_choices(
                OrderedDict(zip([1, 2, 3, 4], [0.7, 0.2, 0.05, 0.05], strict=True)),
                1,
            )[0],
            created_at=now,
            updated_at=now,
            returned_at=None,
            shipped_at=None,
            delivered_at=None,
            cancelled_at=None,
        )

    def __str__(self):
        return f"Order(id={self.id}, user_id={self.user_id}, status='{self.status}', items={self.num_of_items})"

    def update_status(self, fake: Faker, return_probability: float = 0.02) -> Self:
        status_changed = False

        if self.status == OrderStatus.PROCESSING.value:
            # Transition from Processing to either Shipped or Cancelled
            new_status = fake.random_element(
                elements=OrderedDict(
                    [
                        (OrderStatus.SHIPPED.value, 0.95),
                        (OrderStatus.CANCELLED.value, 0.05),
                    ]
                )
            )
            if new_status == OrderStatus.SHIPPED.value:
                self.status = OrderStatus.SHIPPED.value
                self.shipped_at = utcnow()
            else:
                self.status = OrderStatus.CANCELLED.value
                self.cancelled_at = utcnow()
            status_changed = True

        elif self.status == OrderStatus.SHIPPED.value:
            # Deterministic transition from Shipped to Delivered
            self.status = OrderStatus.DELIVERED.value
            self.delivered_at = utcnow()
            status_changed = True

        elif self.status == OrderStatus.DELIVERED.value:
            # Probabilistic transition from Delivered to Returned
            if random.random() < return_probability:
                self.status = OrderStatus.RETURNED.value
                self.returned_at = utcnow()
                status_changed = True

        if status_changed:
            self.updated_at = utcnow()
        return self


class OrderItem(Base):
    __tablename__ = "order_items"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    order_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), index=True
    )
    product_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("products.id"))
    status: Mapped[str]
    quantity: Mapped[int]
    sale_price: Mapped[Decimal] = mapped_column(Money)
    created_at: Mapped[datetime.datetime]
    updated_at: Mapped[datetime.datetime]
    shipped_at: Mapped[datetime.datetime | None]
    delivered_at: Mapped[datetime.datetime | None]
    returned_at: Mapped[datetime.datetime | None]
    cancelled_at: Mapped[datetime.datetime | None]

    order: Mapped[Order] = relationship(back_populates="items")

    @classmethod
    def new(cls, order: Order, fake: Faker) -> Self:
        product_id = fake.random_element(list(PRODUCT_MAP.keys()))
        return cls(
            id=uuid.uuid4(),
            order=order,
            product_id=product_id,
            status=order.status,
            quantity=fake.random_element(range(1, 4)),
            sale_price=PRODUCT_MAP[product_id]["retail_price"],
            created_at=order.created_at,
            updated_at=order.updated_at,
            shipped_at=order.shipped_at,
            delivered_at=order.delivered_at,
            returned_at=order.returned_at,
            cancelled_at=order.cancelled_at,
        )

    def __str__(self):
        return f"OrderItem(id={self.id}, order_id={self.order_id}, product_id={self.product_id}, status={self.status}, quantity={self.quantity})"

    def update_status(self, order: Order) -> Self:
        self.status = order.status
        self.updated_at = order.updated_at
        self.shipped_at = order.shipped_at
        self.delivered_at = order.delivered_at
        self.returned_at = order.returned_at
        self.cancelled_at = order.cancelled_at
        return self


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        # Lets the purge task find old anonymous events without scanning.
        Index("ix_events_ghost_created_at", "created_at", postgresql_where=text("user_id IS NULL")),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"), index=True)
    sequence_number: Mapped[int]
    session_id: Mapped[uuid.UUID]
    ip_address: Mapped[str]
    city: Mapped[str]
    state: Mapped[str]
    postal_code: Mapped[str]
    browser: Mapped[str]
    traffic_source: Mapped[str]
    uri: Mapped[str]
    event_type: Mapped[str]
    created_at: Mapped[datetime.datetime]

    @staticmethod
    def new(
        user: User | None,
        order_item: OrderItem | None,
        event_category: str,
        fake: Faker,
    ) -> list[Self]:
        if event_category in ["purchase", "return", "cancel"]:
            assert order_item is not None
            user_id = user.id
            city = user.city
            state = user.state
            postal_code = user.postal_code
            product_id = order_item.product_id
            order_item_id = order_item.id
            if event_category == "purchase":
                created_at = order_item.created_at
                event_types = list(
                    set(fake.random_choices(["home", "department", "product"], 3))
                ) + ["cart", "purchase"]
            else:
                created_at = utcnow()
                event_types = ["product", "cart", event_category]
        elif event_category == "ghost":
            location = get_location()
            user_id = None
            city = location["city"]
            state = location["state"]
            postal_code = location["postal_code"]
            product_id = fake.random_element(list(PRODUCT_MAP.keys()))
            order_item_id = None
            created_at = utcnow()
            event_types = fake.random_elements(
                [
                    "home",
                    "department",
                    "category",
                    "product",
                    "cancel",
                    "purchase",
                    "return",
                ],
                length=fake.random_element(range(3, 7)),
            )
        else:
            raise RuntimeError(
                f"Unsupported event category: '{event_category}'. Allowed categories are: {', '.join(sorted(['purchase', 'cancel', 'ghost']))}."
            )
        session_id = uuid.uuid4()
        ip_address = fake.ipv4()
        browser = fake.random_choices(
            OrderedDict(
                zip(
                    ["IE", "Edge", "Chrome", "Safari", "Firefox", "Other"],
                    [0.05, 0.1, 0.45, 0.2, 0.15, 0.05],
                    strict=True,
                )
            ),
            1,
        )[0]
        traffic_source = fake.random_choices(
            OrderedDict(
                zip(
                    ["Email", "Adwords", "Organic", "YouTube", "Facebook"],
                    [0.45, 0.3, 0.05, 0.1, 0.1],
                    strict=True,
                )
            ),
            1,
        )[0]
        events = [
            Event(
                id=uuid.uuid4(),
                user_id=user_id,
                sequence_number=idx + 1,
                session_id=session_id,
                ip_address=ip_address,
                city=city,
                state=state,
                postal_code=postal_code,
                browser=browser,
                traffic_source=traffic_source,
                uri=Event._generate_uri(event_type, order_item_id, product_id),
                event_type=event_type,
                created_at=created_at - Event._calculate_event_delay(len(event_types), idx, fake),
            )
            for idx, event_type in enumerate(event_types)
        ]
        return events

    def __str__(self):
        return f"Event(id={self.id}, is_ghost={self.user_id is None}, sequence_number={self.sequence_number}, event_type={self.event_type}, created_at={self.created_at})"

    @staticmethod
    def _generate_uri(event_type: str, item_id: uuid.UUID | None, product_id: int) -> str:
        if event_type == "product":
            return f"/{event_type}/{product_id}"
        elif event_type == "department":
            department = PRODUCT_MAP[product_id]["department"]
            category = PRODUCT_MAP[product_id]["category"]
            return f"/{event_type}/{department}/category/{category}"
        elif event_type in ["cancel", "return"]:
            return f"/{event_type}/item/{item_id}" if item_id is not None else f"/{event_type}"
        else:
            return f"/{event_type}"

    @staticmethod
    def _calculate_event_delay(num_events: int, idx: int, fake: Faker) -> datetime.timedelta:
        if num_events == idx + 1:
            return datetime.timedelta(seconds=0)
        base_delay = (num_events - idx + 1) * 20
        jitter = fake.random_element(range(1, 10))
        return datetime.timedelta(seconds=base_delay + jitter)
