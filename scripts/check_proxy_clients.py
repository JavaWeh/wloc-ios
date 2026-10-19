"""Verify generated adapters are reproducible without rewriting tracked files."""
from pathlib import Path
from build_proxy_clients import outputs, CLIENTS

ROOT = Path(__file__).resolve().parents[1]
for name, expected in outputs().items():
    actual = (ROOT / 'ProxyClients/v3' / name).read_text(encoding='utf-8')
    assert actual == expected, f'Generated adapter drift: {name}'
    assert '127.0.0.1' not in actual and 'localhost' not in actual
assert len(CLIENTS) == 5
print('Five proxy adapters: reproducible, no temporary runtime sources')
