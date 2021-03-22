import re

exception_pattern = re.compile(r"^(\w+)\(")


def get_exception_class(exception_name: str) -> str:
    m = exception_pattern.match(exception_name)
    return m.group(1)
