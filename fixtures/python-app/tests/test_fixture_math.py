from fixture_math import add, sub


def test_add() -> None:
    assert add(2, 2) == 4


def test_sub() -> None:
    assert sub(5, 3) == 2
