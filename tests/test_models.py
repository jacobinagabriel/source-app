import pytest
from faker import Faker

from source_app.models import Event, EventCategory, Order, OrderItem, OrderStatus, User


@pytest.fixture
def fake() -> Faker:
    Faker.seed(42)
    return Faker()


def test_new_user_has_location(fake):
    user = User.new(fake=fake)
    assert user.id and user.country and user.city
    assert 12 <= user.age <= 70


def test_order_status_moves_forward(fake):
    order = Order.new(user=User.new(fake=fake), fake=fake)
    assert order.status == OrderStatus.PROCESSING.value

    order.update_status(fake=fake)
    assert order.status in {OrderStatus.SHIPPED.value, OrderStatus.CANCELLED.value}


def test_order_item_follows_order(fake):
    order = Order.new(user=User.new(fake=fake), fake=fake)
    item = OrderItem.new(order=order, fake=fake)
    order.update_status(fake=fake)

    item.update_status(order=order)
    assert item.status == order.status


def test_ghost_events_have_no_user(fake):
    events = Event.new(
        user=None, order_item=None, event_category=EventCategory.GHOST.value, fake=fake
    )
    assert events
    assert all(e.user_id is None for e in events)
    assert [e.sequence_number for e in events] == list(range(1, len(events) + 1))
