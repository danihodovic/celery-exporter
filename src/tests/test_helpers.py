from src.helpers import get_exception_class


def test_get_exception_class():
    assert get_exception_class(exception_text='ValueError("some error")') == 'ValueError'
