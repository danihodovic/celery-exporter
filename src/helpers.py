import re

exception_pattern = re.compile(r"^(\w+)\(")


def get_exception_class(exception_text: str) -> str:
    m = exception_pattern.match(exception_text)
    return m.group(1)
