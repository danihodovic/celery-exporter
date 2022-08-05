from .exporter import transform_option_value


def test_transform_option_value():
    test_cases = [
        {"input": "1423", "expected": 1423},
        {"input": '{"password": "pass"}', "expected": {"password": "pass"}},
        {
            "input": '{invalid_json: "value"}',
            "expected": '{invalid_json: "value"}',
        },
        {"input": "my_master", "expected": "my_master"},
    ]

    for case in test_cases:
        assert transform_option_value(case["input"]) == case["expected"]
